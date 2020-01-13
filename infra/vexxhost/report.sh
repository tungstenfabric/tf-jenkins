#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

MAX_DURATION="259200"

LOCKED=$(nova list --tags-any "SLAVE=vexxhost" --status ACTIVE --field locked,name | grep 'True' | tr -d '|' | awk '{print $1}' || true)
[[ -z "$LOCKED" ]] && exit

C_DATE=$(date +%s)
for i in $LOCKED; do
  echo $i
  L_DATE=$(date --date $(nova show $i | grep 'OS-SRV-USG:launched_at' | tr -d '|' | awk '{print $NF}') +%s)
  DURATION=$(($C_DATE - $L_DATE))
  if [[ "$DURATION" -ge "$MAX_DURATION" ]]; then
   EXCEED+=($i)
  fi
done
[[ "${#EXCEED[*]}" -eq "0" ]] && exit

for h in "${EXCEED[@]}"; do
  echo "${h} $(openstack server show ${h} -f json | jq -r '.name')" >> vexxhost.report.txt
done
