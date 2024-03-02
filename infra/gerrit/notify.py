#!/usr/bin/env python3

import argparse
import logging
import sys
import traceback
import warnings
warnings.filterwarnings("ignore")

import gerrit_utils


def dbg(msg):
    print("DEBUG: " + msg)


def err(msg):
    print("ERROR: " + msg)


class InvalidLabelError(Exception):
    pass


def parse_labels(labels):
    result = dict()
    if not labels:
        return result
    for label in labels:
        kv = label.split('=')
        if len(kv) != 2:
            raise InvalidLabelError("Label format is invalid %s" % label)
        result[kv[0].strip()] = kv[1].strip()
    return result


def patch_labels(labels_, change_):
    k = 'Verified'
    if k not in labels_:
        return labels_

    if change_.is_active:
        return labels_

    V = change_.labels.get(k, {}).get('all', [])
    v = min(list(map(lambda r_: int(r_.get('value', 0)), V)))
    if v > int(labels_[k]):
        del labels_[k]

    return labels_


def main():
    parser = argparse.ArgumentParser(
        description="TF tool for pushing messages to Gerrit review")
    parser.add_argument("--gerrit", help="Gerrit URL", dest="gerrit", type=str)
    parser.add_argument("--review", help="Review ID", dest="review", type=str)
    parser.add_argument("--patchset", help="Patch Set ID", dest="patchset", type=str)
    parser.add_argument(
        "--branch",
        help="Branch (optional, it is mundatory in case of cherry-picks)",
        dest="branch", type=str)
    parser.add_argument("--user", help="Gerrit user", dest="user", type=str)
    parser.add_argument(
        "--password", help="Gerrit API password",
        dest="password", type=str)
    parser.add_argument("--message", help="Message", dest="message", type=str)
    parser.add_argument(
        "--labels", help="Labels in format k1=v1 k2=v2",
        metavar="KEY=VALUE", nargs='+')
    parser.add_argument(
        "--submit", help="Submit review to merge",
        action="store_true", default=False)
    args = parser.parse_args()

    try:
        gerrit = gerrit_utils.Gerrit(args.gerrit, args.user, args.password)
        change = gerrit.get_current_change(args.review, args.branch, opened_only=False)
        labels = patch_labels(parse_labels(args.labels), change)
        gerrit.push_message(change, args.message, args.patchset, labels=labels)
        if args.submit:
            gerrit.submit(change, args.patchset)
    except Exception as e:
        print(traceback.format_exc())
        err("ERROR: failed to push message: %s" % e)
        sys.exit(1)


if __name__ == "__main__":
    main()
