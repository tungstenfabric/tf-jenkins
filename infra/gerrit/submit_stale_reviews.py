#!/usr/bin/env python3

import argparse
import logging
import sys
import traceback

import gerrit_utils


def info(msg):
    logging.info(msg)


def err(msg):
    logging.error(msg)


def main():
    parser = argparse.ArgumentParser(
        description="TF tool for auto-submitting stale Gerrit reviews")
    parser.add_argument("--debug", dest="debug", action="store_true")
    parser.add_argument("--gerrit", help="Gerrit URL", dest="gerrit", type=str)
    parser.add_argument("--branch", required=False,
        help="Branch (optional, it is mundatory in case of cherry-picks)",
        dest="branch", type=str)
    parser.add_argument("--user", help="Gerrit user", dest="user", type=str)
    parser.add_argument("--password", help="Gerrit API password",
        dest="password", type=str)
    args = parser.parse_args()

    log_level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(level=log_level)
    try:
        gerrit = gerrit_utils.Gerrit(args.gerrit, args.user, args.password)
        expert = gerrit_utils.Expert(gerrit)
        for c in filter(lambda c_: expert.is_eligible_for_submit(c_), gerrit.list_active_changes(args.branch)):
            info('submitting review #%s/%s' % (str(c.number), str(c.revision_number)))
            gerrit.submit(c, c.revision_number)

    except Exception as e:
        print(traceback.format_exc())
        err("ERROR: failed to check approvals: %s" % e)
        sys.exit(1)


if __name__ == "__main__":
    main()
