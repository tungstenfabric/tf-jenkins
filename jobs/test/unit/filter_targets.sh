#!/bin/bash -eE
set -o pipefail

#[ "${DEBUG,,}" == "true" ] && set -x

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
agent=",controller/src/agent:test,controller/src/cat:test,"
bgp=",controller/src/bgp:test,"
opserver=",src/contrail-analytics/contrail-opserver:test,"

group_one=",controller/src/stats:test,contrail-nodemgr:test,vrouter-py-ut:test,"
group_one+="controller/src/vcenter-import:test,vcenter-manager:test,vcenter-fabric-manager:test,"
group_one+="controller/src/config/svc_monitor:test,controller/src/config/schema-transformer:test,"
group_one+="controller/src/container/kube-manager:test,"

if [[ "$TARGET_SET" == "agent" ]]; then
  for target in $(echo $agent | tr ',' ' ') ; do
    if echo ",$UNITTEST_TARGETS," | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
elif [[ "$TARGET_SET" == "bgp" ]]; then
  for target in $(echo $bgp | tr ',' ' ') ; do
    if echo ",$UNITTEST_TARGETS," | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
elif [[ "$TARGET_SET" == "opserver" ]]; then
  for target in $(echo $opserver | tr ',' ' ') ; do
    if echo ",$UNITTEST_TARGETS," | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
elif [[ "$TARGET_SET" == "group_one" ]]; then
  # all analytics except opserver + some targets
  for target in $(echo "$UNITTEST_TARGETS" | tr ',' ' ') ; do
    if [[ "$target" =~ ^src/contrail-analytics/.*$ && "$target" != "$opserver" ]] ; then
      echo "$target" >> "$targets_file"
    elif echo ",$group_one," | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
elif [[ "$TARGET_SET" == "UNGROUPED" ]]; then
  excludes="${agent}${bgp}${opserver}${group_one}"
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
