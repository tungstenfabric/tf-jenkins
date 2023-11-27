#!/bin/bash -eE
set -o pipefail

# to cleanup all workers created by current pipeline

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/functions.sh"
source "$WORKSPACE/global.env"


# TODO: check if it's locked and do not fail job

if TERMINATION_LIST=$(list_instances PipelineBuildTag=${PIPELINE_BUILD_TAG}) ; then
  if DOWN_LIST=$(list_instances PipelineBuildTag=${PIPELINE_BUILD_TAG} DOWN=) ; then
    down_instances $DOWN_LIST || true
  fi

  volumes=$(get_volume_list $TERMINATION_LIST)
  for instance in $TERMINATION_LIST ; do
    openstack server show $instance
  done

  echo "INFO: Instances to terminate: $TERMINATION_LIST"
  openstack server delete --wait $(echo "$TERMINATION_LIST")
  if [[ -n "$volumes" ]] ; then
    openstack volume delete $volumes
  fi
fi