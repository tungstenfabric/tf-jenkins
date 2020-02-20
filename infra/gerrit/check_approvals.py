#!/usr/bin/env python3

import argparse
import logging
import sys
import traceback

from gerrit import Gerrit, Change


def dbg(msg):
    logging.debug(msg)


def err(msg):
    logging.error(msg)


def ready_to_submit(change, approvals):
    for i in approvals:
        # it is expected to have at lease 2 elements 'label:key' ,
        # optionally 3: 'label:key:value'
        label_name, key_name, approval_value, *_ = i.split(':') + [None]
        label = change.labels.get(label_name, {})
        dbg("label_name: %s, key_name: %s, approval_value: %s" %(label_name, key_name, approval_value))
        if key_name not in label:
            dbg("There is no %s in label" % key_name)
            return False
        if approval_value is None:
            dbg("approval_value is not provideded, just check presence of the key")
            continue
        value = label.get('value', None)
        if str(value) != str(approval_value):
            dbg("label value %s doesnt match thr approval_value %s" % (value, approval_value))
            return False
    return True


def main():
    parser = argparse.ArgumentParser(
        description="TF tool for pushing messages to Gerrit review")
    parser.add_argument("--debug", dest="debug", action="store_true")
    parser.add_argument("--gerrit", help="Gerrit URL", dest="gerrit", type=str)
    parser.add_argument("--review", help="Review ID", dest="review", type=str)
    parser.add_argument("--branch",
        help="Branch (optional, it is mundatory in case of cherry-picks)",
        dest="branch", type=str)
    parser.add_argument("--approvals",
        help="List of approvals to check. "
             "Format: <Name:Key[:Value>]>,<Name:Key>,...\n"
             "If Value is not provided then just checks if Key is present\n"
             "E.g. 'Verified:recommended:1,Code-Review:approved,Approved:approved'",
        dest="approvals", type=str,
        default='Verified:recommended:1,Code-Review:approved,Approved:approved')
    parser.add_argument("--user", help="Gerrit user", dest="user", type=str)
    parser.add_argument("--password", help="Gerrit API password",
        dest="password", type=str)
    args = parser.parse_args()

    log_level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(level=log_level)
    try:
        gerrit = Gerrit(args.gerrit, args.user, args.password)
        change = gerrit.get_current_change(args.review, branch=args.branch)
        dbg("Labels in change: %s" % change.labels)
        dbg("Expected approvals: %s" % args.approvals)
        if not ready_to_submit(change, args.approvals.split(',')):
            dbg("Not Ready to submit")
            sys.exit(2)
        dbg("Ready to submit")
    except Exception as e:
        print(traceback.format_exc())
        err("ERROR: failed to check approvals: %s" % e)
        sys.exit(1)


if __name__ == "__main__":
    main()
