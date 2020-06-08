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


def is_eligible_for_gating(expert_, change_):
    if not expert_.is_eligible_for_gating(change_):
        dbg("Not Ready for gating")
        sys.exit(2)

    dbg("Ready to gate")


def is_eligible_for_submit(expert_, change_):
    if not expert_.is_eligible_for_submit(change_):
        dbg("Not Ready to submit")
        sys.exit(2)

    dbg("Ready to submit")


def main():
    parser = argparse.ArgumentParser(
        description="TF tool for pushing messages to Gerrit review")
    parser.add_argument("--strategy", help="What to check: gate or submit", dest="strategy", type=str)
    parser.add_argument("--debug", dest="debug", action="store_true")
    parser.add_argument("--gerrit", help="Gerrit URL", dest="gerrit", type=str)
    parser.add_argument("--review", help="Review ID", dest="review", type=str)
    parser.add_argument(
        "--branch",
        help="Branch (optional, it is mandatory in case of cherry-picks)",
        dest="branch", type=str)
    parser.add_argument("--user", help="Gerrit user", dest="user", type=str)
    parser.add_argument(
        "--password", help="Gerrit API password",
        dest="password", type=str)
    args = parser.parse_args()

    log_level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(level=log_level)

    strategy_hooks = {
        'gate': 'is_eligible_for_gating',
        'submit': 'is_eligible_for_submit'
    }
    if args.strategy not in strategy_hooks:
        err("ERROR: Unknown strategy - {}".format(args.strategy))
        return 1
    try:
        gerrit = gerrit_utils.Gerrit(args.gerrit, args.user, args.password)
        expert = gerrit_utils.Expert(gerrit)
        func = getattr(expert, strategy_hooks[args.strategy])
        change = gerrit.get_current_change(args.review, args.branch)
        if change and not func(change):
            err("Not Ready to {}".format(args.strategy))
            return 1

        dbg("Ready to {}".format(args.strategy))
    except Exception as e:
        print(traceback.format_exc())
        err("ERROR: failed to check approvals: %s" % e)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
