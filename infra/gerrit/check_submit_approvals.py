#!/usr/bin/env python3

import sys
import check_approvals

def is_eligible_for_submit(expert_, change_):
    if expert_.is_eligible_for_submit(change_):
        check_approvals.dbg("Ready to submit")
        sys.exit(2)
    else:
        check_approvals.dbg("Not Ready to submit")
        sys.exit(2)
#    check_approvals.dbg("Ready to submit")

if __name__ == "__main__":
    check_approvals.main(is_eligible_for_submit)
