#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

env|sort

exit 0

rsync tf-dev-env $IP:
cat <<EOF | ssh $IP
export $??_REGISTRY=???_REGISTRY
export ??_TAG=??_TAG
export DEV_ENV_IMAGE=???
??/tf-dev-env/run.sh build
EOF
