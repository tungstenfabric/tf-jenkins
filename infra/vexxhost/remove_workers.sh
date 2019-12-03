#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$WORKSPACE/global.env"

DEFAULT_ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
ENV_FILE=${ENV_FILE:-$DEFAULT_ENV_FILE}
source $ENV_FILE

openstack server delete --wait $instance_id
openstack volume delete --force $volume_id
