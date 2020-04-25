#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_dir="$(realpath $(dirname "$0"))"

source "$my_dir/definitions"

# TARGET_SET is a parameter for this job
# can be name of set or UNGROUPED for targets not in sets but in ci_unittest.json or empty
# empty/absent means early exit with full UNITTEST_TARGETS
# UNITTEST_TARGETS must be present in env - it's inherited from fetch job

if [[ -z "$TARGET_SET" ]]; then
  echo "$UNITTEST_TARGETS" | tr ',' '\n' > $WORKSPACE/unittest_targets.lst
  exit
fi

targets_file="$WORKSPACE/unittest_targets.lst"
rm -f "$targets_file"
touch "$targets_file"

# hardcoded sets of targets
#sets = [
#  'agent': ['controller/src/agent:test', 'controller/src/cat:test'],
#  'bgp': ['controller/src/bgp:test'],
#  'opserver': ['src/contrail-analytics/contrail-collector:test'],
#  'analytics': ['src/contrail-analytics/.*' and not opserver],
#  'UNGROUPED': all excluding above
#]
# intersect set[TARGET_SET] with UNITTEST_TARGETS and store the result in $WORKSPACE/unittest_targets.lst

if [[ "$TARGET_SET" == "agent" ]]; then
  for target in 'controller/src/agent:test' 'controller/src/cat:test' ; do
    if echo ",$UNITTEST_TARGETS," | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
elif [[ "$TARGET_SET" == "bgp" ]]; then
  if echo ",$UNITTEST_TARGETS," | grep -q ",controller/src/bgp:test," ; then
    echo "controller/src/bgp:test" >> "$targets_file"
  fi
elif [[ "$TARGET_SET" == "opserver" ]]; then
  if echo ",$UNITTEST_TARGETS," | grep -q ",src/contrail-analytics/contrail-collector:test," ; then
    echo "src/contrail-analytics/contrail-collector:test" >> "$targets_file"
  fi
elif [[ "$TARGET_SET" == "analytics" ]]; then
  for target in $(echo "$UNITTEST_TARGETS" | tr ',' ' ') ; do
    if [[ "$target" =~ ^src/contrail-analytics/.*$ && "$target" != "src/contrail-analytics/contrail-opserver:test" ]] ; then
      echo "$target" >> "$targets_file"
    fi
  done
elif [[ "$TARGET_SET" == "UNGROUPED" ]]; then
  excludes=',controller/src/agent:test,controller/src/cat:test,controller/src/bgp:test,'
  for target in $(echo "$UNITTEST_TARGETS" | tr ',' ' ') ; do
    if [[ ! "$target" =~ ^src/contrail-analytics/.*$ ]] && ! echo "$excludes" | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
else
  echo "ERROR: unknown target $TARGET_SET"
  exit 1
fi

if [[ "$(cat $WORKSPACE/unittest_targets.lst | wc -l | xargs)" == '0' ]]; then
  echo "INFO: filtered set is empty"
  exit 1
fi

echo "INFO: filtered set:"
cat $WORKSPACE/unittest_targets.lst
