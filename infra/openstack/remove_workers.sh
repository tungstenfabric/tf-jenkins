#!/bin/bash

# to remove just job's workers

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/functions.sh"
source "$WORKSPACE/global.env"

instance_ids=$(echo $INSTANCE_IDS | sed 's/,/ /g')

for instance_id in $instance_ids ; do
  if nova show "$instance_id" | grep 'locked' | grep 'False' ; then
    if down_instances $instance_id ; then
      openstack server show $instance_id
      volumes=$(openstack server show $instance_id |  grep volumes_attached | awk -F[\'\'] '{print $2}')
      openstack server delete --wait "$instance_id"
      if [[ -n "$volumes" ]] ; then
        openstack volume delete $volumes
      fi
    fi
  fi
done
