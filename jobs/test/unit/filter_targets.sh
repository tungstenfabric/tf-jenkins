#!/bin/bash -eE
set -o pipefail
set -x

my_dir="$(realpath $(dirname "$0"))"

source "$my_dir/definitions"

targets_file="$WORKSPACE/unittest_targets.lst"
rm -f "$targets_file"
touch "$targets_file"

# hardcoded sets of targets
agent=",controller/src/agent:test,controller/src/cat:test,"
bgp=",controller/src/bgp:test,controller/src/cat:test_upgrade,"
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
elif [[ "$TARGET_SET" == "group-one" ]]; then
  # all analytics except opserver + some targets
  for target in $(echo "$UNITTEST_TARGETS" | tr ',' ' ') ; do
    if [[ "$target" =~ ^src/contrail-analytics/.*$ && ! "$opserver" =~ "$target" ]] ; then
      echo "$target" >> "$targets_file"
    elif echo ",$group_one," | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
elif [[ "$TARGET_SET" == "ungrouped" ]]; then
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
