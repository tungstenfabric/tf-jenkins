#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

# stackrc file is prepared by pipeline based on
# previous job's artifacts
export stackrc_file=${stackrc_file:-"deps.${JOB_NAME}.${JOB_RND}.env"}
source $WORKSPACE/$stackrc_file

${my_dir}/../common/collect_logs.sh rhosp-operator
