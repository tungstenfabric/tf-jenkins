#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

export stackrc_file=${stackrc_file:-"stackrc.$JOB_NAME.env"}
source $WORKSPACE/$stackrc_file

${my_dir}/../common/run_stage.sh rhosp platform
