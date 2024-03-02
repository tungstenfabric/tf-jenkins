#!/usr/bin/env python3

import argparse
import logging
import sys
import traceback
import warnings
warnings.filterwarnings("ignore")

import gerrit_utils


def main():
    parser = argparse.ArgumentParser(
        description="TF tool for pushing messages to Gerrit review")
    parser.add_argument("--strategy", help="What to check: gate or submit", dest="strategy", type=str)
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

    try:
        gerrit = gerrit_utils.Gerrit(args.gerrit, args.user, args.password)
        # relies to default behaviour of get_current_change(opened_only=True)
        # if review is merged then None will be returned
        return 1 if gerrit.get_current_change(args.review, args.branch) else 0
    except Exception:
        print(traceback.format_exc())
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
