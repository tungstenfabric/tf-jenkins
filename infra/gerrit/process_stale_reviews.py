#!/usr/bin/env python3

import argparse
import datetime
import logging
import warnings
warnings.filterwarnings("ignore")

import gerrit_utils


def info(msg):
    logging.info(msg)


def err(msg):
    logging.error(msg)


def is_eligible_for_gating(expert, change):
    if not expert.is_eligible_for_gating(change):
        return False

    # check if gating is not running
    # check last comment in review and do further check if it's older than 5 minutes
    # to avoid fault detection and races - right after approval gating can be started but
    # script can miss jenkins job and start gating twice
    if change.updated > datetime.datetime.utcnow() + datetime.timedelta(minutes=5):
        return False

    # check for running jobs is bot required - gate job clears Verified label at start
    # script can't reach this point in this case. If we here than Verified is -2 or +1 and gating
    # was not started
    return True


def is_eligible_for_submit(expert, change):
    return expert.is_eligible_for_submit(change)


def main():
    parser = argparse.ArgumentParser(
        description="TF tool for auto-submitting stale Gerrit reviews")
    parser.add_argument("--strategy", dest="strategy", type=str)
    parser.add_argument("--debug", dest="debug", action="store_true")
    parser.add_argument("--gerrit", help="Gerrit URL", dest="gerrit", type=str)
    parser.add_argument(
        "--branch", required=False,
        help="Branch (optional, it is mundatory in case of cherry-picks)",
        dest="branch", type=str)
    parser.add_argument("--user", help="Gerrit user", dest="user", type=str)
    parser.add_argument(
        "--password", help="Gerrit API password",
        dest="password", type=str)
    args = parser.parse_args()

    log_level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(level=log_level)

    gerrit = gerrit_utils.Gerrit(args.gerrit, args.user, args.password)
    expert = gerrit_utils.Expert(gerrit)

    strategy_hooks = {
        'gate': (is_eligible_for_gating, gerrit.gate),
        'submit': (is_eligible_for_submit, gerrit.submit)
    }
    if args.strategy not in strategy_hooks:
        err("ERROR: Unknown strategy - {}".format(args.strategy))
        return 1

    check_op = strategy_hooks[args.strategy][0]
    process_op = strategy_hooks[args.strategy][1]
    labels = ['Code-Review=2', 'Approved=1']
    for commit in gerrit.list_active_changes(args.branch, labels=labels):
        try:
            info('processing review #%s/%s' % (str(commit.number), str(commit.revision_number)))
            if check_op(expert, commit):
                info('review is ready to %s' % args.strategy)
                process_op(commit, commit.revision_number)
        except Exception as e:
            info('failed to check review #{}/{}: {}'.format(commit.number, commit.revision_number, e))


if __name__ == "__main__":
    main()
