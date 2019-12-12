#!/usr/bin/env python

import argparse
import collections
import copy
import json
import logging
import os
import re
import requests
import sys
import traceback


def dbg(msg):
    logging.debug(msg)


def err(msg):
    logging.error(msg)


class GerritRequestError(Exception):
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
        res = requests.post(url, data, auth=self._auth)
        if not res.ok:
            msg = "Failed request %s with code %s" % (res.url, res.status_code)
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


class Gerrit(object):
    def __init__(self, gerrit_url, user, password):
        self._url = gerrit_url.rstrip('/')
        self._session = Session(self._url, user, password)

    def _get_current_change(self, review_id, branch):
        params='q=change:%s' % review_id
        if branch:
            params+=' branch:%s' % branch
        params+='&o=CURRENT_COMMIT&o=CURRENT_REVISION'
        return self._session.get('/changes/', params=params)

    def get_current_change(self, review_id, branch=None):
        res = self._get_current_change(review_id, branch)
        if len(res) == 0:
            msg = "Review %s (branch=%s) not found" % (review_id, branch)
            raise GerritRequestError(msg)
        return Change(res[0])


    def push_message(self, change, message):
        data = {
            "drafts": "PUBLISH_ALL_REVISIONS",
            "labels": {},
            "message": message,
            "reviewers": []
        }
        url = "/changes/%s/revisions/%s/review" % \
            (change.id, change.revision_number)
        self._session.post(url, data=data)


def main():
    parser = argparse.ArgumentParser(
        description="TF tool for pushing messages to Gerrit review")
    parser.add_argument("--debug", dest="debug", action="store_true")
    parser.add_argument("--gerrit", help="Gerrit URL", dest="gerrit", type=str)
    parser.add_argument("--review", help="Review ID", dest="review", type=str)
    parser.add_argument("--branch",
        help="Branch (optional, it is mundatory in case of cherry-picks)",
        dest="branch", type=str)
    parser.add_argument("--user", help="Gerrit user", dest="user", type=str)
    parser.add_argument("--password", help="Gerrit API password",
        dest="password", type=str)
    parser.add_argument("--message", help="Message", dest="message", type=str)

    args = parser.parse_args()
    log_level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(level=log_level)
    try:
        gerrit = Gerrit(args.gerrit, args.user, args.password)
        change = gerrit.get_current_change(args.review, branch=args.branch)
        gerrit.push_message(change, args.message)
    except Exception as e:
        print(traceback.format_exc())
        err("ERROR: failed to push message: %s" % e)
        sys.exit(1)


if __name__ == "__main__":
    main()
