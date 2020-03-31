#!/usr/bin/env python3

import sys
import check_approvals

def is_eligible_for_gating(expert_, change_):
    if not expert_.is_eligible_for_gating(change_):
        check_approvals.dbg("Not Ready for gating")
        sys.exit(2)

    check_approvals.dbg("Ready to gate")

if __name__ == "__main__":
    check_approvals.main(is_eligible_for_gating)
