#!/usr/bin/env python3

import json
import logging
import re
import requests


DEPENDS_RE = re.compile('depends-on:[ ]*[a-zA-Z0-9]+', re.IGNORECASE)


def dbg(msg):
    logging.debug(msg)


def err(msg):
    logging.error(msg)


class GerritRequestError(Exception):
    pass


class InvalidLabelError(Exception):
    pass


class ParentError(Exception):
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
    def __init__(self, data, gerrit):
        self._data = data
        self._files = None
        self._gerrit = gerrit
        dbg("Change: %s" % self._data)

    def __hash__(self):
        return hash(self.change_id)

    def __eq__(self, value):
        return self.change_id == value.change_id

    def __gt__(self, value):
        return self.change_id > value.change_id

    def __lt__(self, value):
        return self.change_id < value.change_id

    @property
    def id(self):
        return self._data['id']

    @property
    def status(self):
        return self._data['status']

    @property
    def project(self):
        return self._data['project']

    @property
    def branch(self):
        return self._data['branch']

    @property
    def change_id(self):
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
    def files(self):
        return self._files

    def set_files(self, files):
        self._files = files

    @property
    def labels(self):
        return self._data.get('labels', {})

    @property
    def commit_message(self):
        return self._data['revisions'][self.revision]['commit']['message']

    @property
    def parent_sha(self):
        parents = self._data['revisions'][self.revision]['commit']['parents']
        if len(parents) != 1:
            # let's fail on this case to see if can happens
            msg = "Parents list has invalid count {} !!!".format(parents)
            raise ParentError(msg)

        return parents[0]['commit']

    @property
    def is_active(self):
        return 'NEW' == self._data['status']

    @property
    def depends_on(self):
        result = []
        # collect parents by SHA - non-merged review can have only one parent
        parent = self._gerrit.get_change_by_sha(self.parent_sha)
        if parent and parent.is_active:
            result.append(parent.id)
            result += parent.depends_on
        # collect Depends-On from commit message 
        msg = self._data['revisions'][self.revision]['commit']['message']
        for d in DEPENDS_RE.findall(msg):
            review_id = d.split(':')[1].strip()
            change = self._gerrit.get_current_change_smart(review_id, self.branch)
            if change.is_active:
                result.append(review_id)
        dbg("Change: %s: depends_on: %s" % (self._data['change_id'], result))
        return result


class Gerrit(object):
    def __init__(self, gerrit_url, user, password):
        self._url = gerrit_url.rstrip('/')
        self._session = Session(self._url, user, password)

    def _get_current_change(self, review_id, branch):
        params = 'q=change:%s+status:open' % review_id
        if branch:
            params += ' branch:%s' % branch
        params += '&o=CURRENT_COMMIT&o=CURRENT_REVISION&o=DETAILED_LABELS'
        return self._session.get('/changes/', params=params)

    def get_changed_files(self, change):
        raw = self._session.get("/changes/%s/revisions/%s/files" %
            (change.id, change.revision_number))
        res = list()
        for k, _ in raw.items():
            if k != "/COMMIT_MSG":
                res.append(k)
        return res

    def get_current_change(self, review_id, branch):
        # request all branches for review_id to
        # allow cross branches dependencies between projects
        res = self._get_current_change(review_id, None)
        if len(res) == 1:
            # there is no ambiguite, so return the found change 
            return Change(res[0], self)
        # there is ambiquity - try to resolve it by branch
        branches = {i.get('branch'): i for i in res}
        if branch in branches:
            return Change(branches[branch], self)
        # same branch is not found
        # TODO: choose DEFAULT_OPENSTACK_BRANCH if present, then latest openstack branch, then master
        raise GerritRequestError("Review {} (branch={}) not found. Count of result is {}".format(
            review_id, branch, len(res)))

    def get_change_by_sha(self, sha):
        params = 'q=commit:%s&o=CURRENT_COMMIT&o=CURRENT_REVISION&o=DETAILED_LABELS' % sha
        res = self._session.get('/changes/', params=params)
        if len(res) == 1:
            # there is no ambiguity, so return the found change 
            return Change(res[0], self)
        elif len(res) == 0:
            dbg("Cannot find a change for SHA %s" % sha)
            return None
        raise GerritRequestError("Search for SHA %s has too many results" % sha)

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
        return 0 < len(change_.depends_on)

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

