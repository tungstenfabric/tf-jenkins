#!/usr/bin/env python

import argparse
import collections
import copy
import json
import logging
import sys
import traceback

import gerrit_utils


def dbg(msg):
    logging.debug(msg)


def err(msg):
    logging.error(msg)


class DependencyLoopError(Exception):
    pass


def resolve_dependencies(gerrit, change, parent_ids=[]):
    result = [ change ]
    parent_ids.append(change.change_id)
    depends_on_list = change.depends_on
    for i in depends_on_list:
        if i in parent_ids:
            raise DependencyLoopError(
                "There is dependency loop detected: id %s is already in %s" \
                % (i, parent_ids)
            )
        cc = gerrit.get_current_change(i, change.branch)
        result += resolve_dependencies(gerrit, cc, copy.deepcopy(parent_ids))
    return result            


def resolve_files(gerrit, changes_list):
    for i in changes_list:
        i.set_files(gerrit.get_changed_files(i))
    return changes_list


def format_result(changes_list):
    res = list()
    for i in changes_list:
        item = {
            'id': i.change_id,
            'project': i.project,
            'ref': i.ref,
            'number': str(i.number),
            'branch': i.branch
        }
        if i.files:
            item['files'] = i.files
        res.append(item)
    return res


def main():
    parser = argparse.ArgumentParser(
        description="TF tool for Gerrit patchset dependencies resolving")
    parser.add_argument("--debug", dest="debug", action="store_true")
    parser.add_argument("--gerrit", help="Gerrit URL", dest="gerrit", type=str)
    parser.add_argument("--review", help="Review ID", dest="review", type=str)
    parser.add_argument("--branch", help="Branch", dest="branch", type=str)
    parser.add_argument("--changed_files", dest="changed_files", action="store_true")
    parser.add_argument("--output",
        help="Save result into the file instead stdout",
        default=None, dest="output", type=str)
    args = parser.parse_args()
    log_level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(level=log_level)
    try:
        gerrit = gerrit_utils.Gerrit(args.gerrit)
        change = gerrit.get_current_change(args.review, args.branch)
        changes_list = resolve_dependencies(gerrit, change)
        changes_list.reverse()
        changes_list = collections.OrderedDict.fromkeys(changes_list)
        if args.changed_files:
            changes_list = resolve_files(gerrit, changes_list)
        result = format_result(changes_list)
        if args.output:
            with open(args.output, "w") as f:
                json.dump(result, f)
        else:
            print(json.dumps(result))
    except Exception as e:
        print(traceback.format_exc())
        err("ERROR: failed to resolve review dependencies: %s" % e)
        sys.exit(1)


if __name__ == "__main__":
    main()
