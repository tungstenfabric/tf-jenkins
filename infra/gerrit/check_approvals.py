#!/usr/bin/env python3

import argparse
import logging
import sys
import traceback
import warnings
warnings.filterwarnings("ignore")

import gerrit_utils


def dbg(msg):
    logging.debug(msg)


def err(msg):
    logging.error(msg)


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

    log_level = logging.NOTSET if args.debug else logging.INFO

    h = logging.StreamHandler(sys.stdout)
    h.setLevel(log_level)
    h.setFormatter(logging.Formatter('%(asctime)s.%(msecs)03d %(levelname)s: %(message)s', datefmt='%m-%d %H:%M:%S'))

    L = logging.getLogger()
    L.handlers *= 0
    L.addHandler(h)

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
