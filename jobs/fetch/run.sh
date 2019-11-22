#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

exit 0

export $??_REGISTRY=???_REGISTRY
export ??_TAG=??_TAG
export DEV_ENV_IMAGE=???
./src/tungstenfabric/tf-dev-env/run.sh
docker commit ???
docker push $REGISTRY/tf-dev-env-centos:$PATCHSET_ID
