#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
# do it as a latest source to override all exports
if [[ -f ${WORKSPACE}/${JOB_NAME}.env ]]; then
  source ${WORKSPACE}/${JOB_NAME}.env
fi

${my_dir}/run_${BUILD_WORKER["${ENVIRONMENT_OS^^}"]}.sh
