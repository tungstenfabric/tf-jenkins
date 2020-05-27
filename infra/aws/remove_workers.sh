#!/bin/bash -eE
set -o pipefail

# to remove just job's workers

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/functions.sh"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
instance_ids=`cat $ENV_FILE | grep INSTANCE_IDS | cut -d'=' -f2 | sed 's/,/ /g'`

terminate_instances $instance_ids
