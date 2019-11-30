#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$DEPLOY_PLATFORM_PROJECT.env"
source $ENV_FILE

rsync -a -e "ssh $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: Test sanity started"

# TODO: fix uploading test image to tungstenfabric and remove TF_TEST_IMAGE below

cat <<EOF | ssh $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin
export TF_TEST_IMAGE="opencontrailnightly/contrail-test-test:master-latest"
cd src/tungstenfabric/tf-test/contrail-sanity
ORCHESTRATOR=$ORCHESTRATOR ./run.sh
EOF

echo "INFO: Test sanity finished"
