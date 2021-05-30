#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

MAX_DURATION="259200"

LOCKED=$(nova list --tags-any "SLAVE=vexxhost" --status ACTIVE --field locked,name | grep 'True' | tr -d '|' | awk '{print $1}' || true)
if [[ -z "$LOCKED" ]]; then
  exit
fi

C_DATE=$(date +%s)
for i in $LOCKED; do
  echo "INFO: Locked instance to test for duration: $i"
  L_DATE=$(date --date $(nova show $i | grep 'OS-SRV-USG:launched_at' | tr -d '|' | awk '{print $NF}') +%s)
  DURATION=$(($C_DATE - $L_DATE))
  if [[ "$DURATION" -ge "$MAX_DURATION" ]]; then
    EXCEED+=($i)
  fi
done
echo "INFO: Exceed list: ${#EXCEED[@]}"
if [[ "${#EXCEED[*]}" == "0" ]]; then
  exit
fi

report_file="vexxhost.report.txt"
echo "VEXXHOST instances alive more than 3 days:" > $report_file
for h in "${EXCEED[@]}"; do
  echo "${h} $(openstack server show ${h} -f json | jq -r '.name')" >> $report_file
done
