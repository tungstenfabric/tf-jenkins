#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

# transfer patchsets info into sandbox
if [ -e $WORKSPACE/patchsets-info.json ]; then
  mkdir -p $WORKSPACE/src/tungstenfabric/tf-dev-env/input/
  cp -f $WORKSPACE/patchsets-info.json $WORKSPACE/src/tungstenfabric/tf-dev-env/input/
fi

export DEVENV_TAG=${DEVENV_TAG:-stable${TAG_SUFFIX}}

${my_dir}/run_${BUILD_WORKER["${ENVIRONMENT_OS^^}"]}.sh

# save DEVENV_TAG that was pushed by this job
# chidlren jobs may have own TAG_SUFFIX and they shouldn't rely on it
echo "export DEVENV_TAG=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX" > fetch.env

echo "export UNITTEST_TARGETS=$(cat $WORKSPACE/unittest_targets.lst | tr '\n' ',')" >> fetch.env
