#!/usr/bin/env python3

import argparse
import collections
import copy
import json
import logging
import os
import re
import requests


def dbg(msg):
    logging.debug(msg)


def err(msg):
    logging.error(msg)


class GerritRequestError(Exception):
    pass


class InvalidLabelError(Exception):
    pass


class Session(object):
    def __init__(self, url, user, password):
        if user is not None and password is not None:
            self._url = url + "/a"
            self._auth = requests.auth.HTTPBasicAuth(user, password)
        else:
            self._url = url
            self._auth = None

    def _make_url(self, request):
        return self._url + request

    def get(self, request, params=None):
        url = self._make_url(request)
        res = requests.get(url, params=params, auth=self._auth)
        if not res.ok:
            msg = "Failed request %s with code %s" % (res.url, res.status_code)
            raise GerritRequestError(msg)
        response = res.text.strip(')]}\'')
        return json.loads(response)

    def post(self, request, data=None):
        url = self._make_url(request)
        res = requests.post(url, json=data, auth=self._auth)
        if not res.ok:
            msg = "Failed request %s with code %s: %s" % (res.url, res.status_code, res.content)
            raise GerritRequestError(msg)
        response = res.text.strip(')]}\'')


class Change(object):
    def __init__(self, data):
        self._data = data
        dbg("Change: %s" % self._data)

    @property
    def id(self):
        return self._data['id']

    @property
    def short_id(self):
        return self._data['change_id']

    @property
    def revision(self):
        return self._data['current_revision']

    @property
    def ref(self):
        return self._data['revisions'][self.revision]['ref']

    @property
    def number(self):
        return self._data.get('_number', self.ref.split("/")[3])

    @property
    def revision_number(self):
        return self._data['revisions'][self.revision].get(
            '_number', self.ref.split("/")[4])

    @property
    def labels(self):
        return self._data.get('labels', {})

    @property
    def commit_message(self):
        return self._data['revisions'][self.revision]['commit']['message']

    @property
    def parent_sha(self):
        p = self._data['revisions'][self.revision]['commit']['parents']
        if 1 != len(p):
            # let's fail on this case to see if can happens
            dbg("Parents list has invalid count {} !!!".format(p))
            sys.exit(1)

        return p[0]['commit']

    @property
    def is_active(self):
        return 'NEW' == self._data['status']


class Gerrit(object):
    def __init__(self, gerrit_url, user, password):
        self._url = gerrit_url.rstrip('/')
        self._session = Session(self._url, user, password)

    def _get_current_change(self, review_id, branch):
        params='q=change:%s' % review_id
        if branch:
            params+=' branch:%s' % branch
        params+='&o=CURRENT_COMMIT&o=CURRENT_REVISION&o=DETAILED_LABELS'
        return self._session.get('/changes/', params=params)

    def get_current_change(self, review_id, branch=None):
        res = self._get_current_change(review_id, branch)
        if len(res) == 0:
            msg = "Review %s (branch=%s) not found" % (review_id, branch)
            raise GerritRequestError(msg)
        return Change(res[0])

    def get_that_change(self, sha_):
        q = 'q=commit:%s&o=CURRENT_COMMIT&o=CURRENT_REVISION&o=DETAILED_LABELS' % sha_
        m = self._session.get('/changes/', params=q)
        if 1 == len(m):
            # there is no ambiguity, so return the found change 
            return Change(m[0])
        elif 0 == len(m):
            dbg("Cannot find a change for SHA %s" % sha_)
            return None

        raise GerritRequestError("Search for SHA %s has too many results" % sha_)

    def list_active_changes(self, branch_ = None):
        spin = True
        start = 0
        q = 'n=5&o=CURRENT_COMMIT&o=CURRENT_REVISION&o=DETAILED_LABELS&q=status:NEW'
        if branch_:
            q += ' branch:%s' % branch_

        while spin:
            m = self._session.get('/changes/', params='%s&S=%d' % (q, start))
            for c in m:
                start += 1
                spin = c.get('_more_changes', False)
                yield Change(c)

    def push_message(self, change, message, patchset, labels={}):
        data = {
            "labels": labels,
            "message": message,
        }
        dbg("push message data: %s" % data)
        url = "/changes/%s/revisions/%s/review" % \
            (change.id, patchset)
        self._session.post(url, data=data)

    def submit(self, change, patchset):
        data = {
            "wait_for_merge": True
        }
        url = "/changes/%s/revisions/%s/submit" % \
            (change.id, patchset)
        self._session.post(url, data=data)


class Expert(object):
    DEPENDS_RE = re.compile('depends-on:[ ]*[a-zA-Z0-9]+', re.IGNORECASE)

    def __init__(self, gerrit_):
        self.m_gerrit = gerrit_

    def is_mergeable(self, change_):
        R = change_.labels.get('Code-Review', {}).get('all', [])
        if 0 < len(list(filter(lambda r_: -2 == r_.get('value', 0), R))):
            dbg("there is a Code-Review -2")
            return False

        if 0 == len(list(filter(lambda r_: 2 == r_.get('value', 0), R))):
            dbg("there is no Code-Review +2")
            return False

        return True

    def is_approved(self, change_):
        A = change_.labels.get('Approved', {}).get('all', [])
        if 0 < len(list(filter(lambda r_: -1 == r_.get('value', 0), A))):
            dbg("there is an Approved -1")
            return False

        if 0 == len(list(filter(lambda r_: 1 == r_.get('value', 0), A))):
            dbg("there is no Approved +1")
            return False

        return True

    def is_verified(self, change_, factor_):
        f = abs(factor_)
        V = change_.labels.get('Verified', {}).get('all', [])
        if 0 == len(list(filter(lambda r_: f == r_.get('value', 0), V))):
            dbg("there is no Verified +%d" % f)
            return False

        return True

    def has_unmerged_parents(self, change_):
        parents = []
        # collect parents by SHA - non-merged review can have only one parent
        parent = self.m_gerrit.get_that_change(change_.parent_sha)
        if parent and parent.is_active:
            parents.append(parent.id)

        # collect Depends-On from commit message 
        for d in Expert.DEPENDS_RE.findall(change_.commit_message):
            review_id = d.split(':')[1].strip()
            parent = self.m_gerrit.get_current_change(review_id)
            if parent.is_active:
                parents.append(review_id)

        dbg("Change: %s: depends_on: %s" % (change_.short_id, parents))
        return 0 < len(parents)

    def __is_eligible_general_test(self, change_):
        if not change_:
            dbg('a valid change object is required')
            return False

        dbg("Labels in change: %s" % change_.labels)
        if not change_.is_active:
            dbg('the review %s is inactive' % change_.number)
            return False

        return True

    def is_eligible_for_gating(self, change_):
        return self.__is_eligible_general_test(change_) and \
            self.is_mergeable(change_) and self.is_approved(change_) and \
            self.is_verified(change_, 1)

    def is_eligible_for_submit(self, change_):
        return self.__is_eligible_general_test(change_) and \
            self.is_mergeable(change_) and self.is_approved(change_) and \
            self.is_verified(change_, 2) and not self.has_unmerged_parents(change_)

