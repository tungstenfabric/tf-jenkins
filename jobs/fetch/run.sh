#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

echo 'INFO: Run fetch with tf-dev-env'

[ "${DEBUG,,}" == "true" ] && set -x
export CONTAINER_REGISTRY
export CONTRAIL_CONTAINER_TAG="$PATCHSET_ID"
cd src/tungstenfabric/tf-dev-env
# TODO: remove condition
if ./run.sh fetch ; then
  echo "INFO: Fetch finished successfully"
else
  echo "INFO: Fetch failed"
fi

# TODO: commit and push dev-env
