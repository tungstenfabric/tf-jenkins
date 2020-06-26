#!/bin/bash -eE
set -o pipefail

# to remove just job's workers

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/functions.sh"
source "$WORKSPACE/global.env"

instance_ids=$(echo $INSTANCE_IDS | sed 's/,/ /g')

for instance_id in $instance_ids ; do
  if nova show "$instance_id" | grep 'locked' | grep 'False'; then
    down_instances $instance_id || true
    nova delete "$instance_id"
  fi
done
