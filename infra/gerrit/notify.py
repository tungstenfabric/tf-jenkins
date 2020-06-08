#!/usr/bin/env python3

import argparse
import logging
import sys
import traceback

import gerrit_utils


def dbg(msg):
    logging.debug(msg)


def err(msg):
    logging.error(msg)


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


def main():
    parser = argparse.ArgumentParser(
        description="TF tool for pushing messages to Gerrit review")
    parser.add_argument("--debug", dest="debug", action="store_true")
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

    log_level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(level=log_level)
    try:
        gerrit = gerrit_utils.Gerrit(args.gerrit, args.user, args.password)
        change = gerrit.get_current_change(args.review, args.branch, opened_only=False)
        labels = parse_labels(args.labels)
        gerrit.push_message(change, args.message, args.patchset, labels=labels)
        if args.submit:
            gerrit.submit(change, args.patchset)
    except Exception as e:
        print(traceback.format_exc())
        err("ERROR: failed to push message: %s" % e)
        sys.exit(1)


if __name__ == "__main__":
    main()
