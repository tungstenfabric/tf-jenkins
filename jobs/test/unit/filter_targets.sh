#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

# TARGET_SET is a parameter for this job
# can be name of set or UNGROUPED for targets not in sets but in ci_unittest.json or empty
# empty/absent means early exit with full UNITTEST_TARGETS
# UNITTEST_TARGETS must be present in env - it's inherited from fetch job

if [[ -z "TARGET_SET" ]]; then
  echo "$UNITTEST_TARGETS" | tr ',' '\n' > $WORKSPACE/unittest_targets.lst
  exit
fi

# hardcoded sets of targets
#sets = [
#  'agent': ['controller/src/agent:test', 'controller/src/cat:test'],
#  'bgp': ['controller/src/bgp:test'],
#  'opserver': ['src/contrail-analytics/contrail-collector:test'],
#  'analytics': ['src/contrail-analytics/.*' and not opserver],
#]

# intersect set[TARGET_SET] with UNITTEST_TARGETS and store the result in $WORKSPACE/unittest_targets.lst

# return 1 if set is empty
