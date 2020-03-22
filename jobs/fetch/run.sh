#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

${my_dir}/run_${BUILD_WORKER["${ENVIRONMENT_OS^^}"]}.sh

# save DEVENVTAG that was pushed by this job
# chidlren jobs may have own TAG_SUFFIX and they shouldn't rely on it
echo "export DEVENVTAG=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX" > fetch.env
