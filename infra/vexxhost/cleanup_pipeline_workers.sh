#!/bin/bash -eE
set -o pipefail

# to cleanup all workers created by current pipeline

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$WORKSPACE/global.env"

# TODO: check if it's locked and do not fail job

openstack server delete --wait $(nova list --tags "-${PIPELINE_BUILD_TAG}-" --minimal | awk '{print $2}' | grep -v ID | grep -v "^$")
