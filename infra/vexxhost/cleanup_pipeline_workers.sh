#!/bin/bash -eE
set -o pipefail
set -x

# to cleanup all workers created by current pipeline

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$WORKSPACE/global.env"

# TODO: check if it's locked and do not fail job

PIPELINE_VEXXHOST_INSTANCES=""
for i in $(openstack server list -c ID -f value --name jenkins); do
  server_property=$(openstack server show -c properties -f value $i)
  server_pipeline=$(echo ${server_property#Pipeline=} | awk -F\' '{print $2}')
  if [ "$server_pipeline" == "${PIPELINE_BUILD_TAG}" ]; then
    PIPELINE_VEXXHOST_INSTANCES="$i $PIPELINE_VEXXHOST_INSTANCES"
  fi
done
openstack server delete --wait $PIPELINE_VEXXHOST_INSTANCES

PIPELINE_VEXXHOST_VOLUMES=""
for v in $(openstack volume list -c ID -f value --name jenkins); do
  volume_property=$(openstack volume show -c properties -f value $v)
  volume_pipeline=$(echo ${volume_property#Pipeline=} | awk -F\' '{print $2}')
  if [ "$volume_pipeline" == "${PIPELINE_BUILD_TAG}" ]; then
    PIPELINE_VEXXHOST_VOLUMES="$v $PIPELINE_VOLUMES"
  fi
done
openstack volume delete --force $PIPELINE_VEXXHOST_VOLUMES
