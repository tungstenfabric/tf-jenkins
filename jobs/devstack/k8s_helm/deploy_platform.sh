#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
echo "ORCHESTRATOR=kubernetes" >> "$ENV_FILE"
source $ENV_FILE

echo 'INFO: Deploy platform for $JOB_NAME'

rsync -a -e "ssh $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

cat <<EOF | ssh $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export DEBUG=$DEBUG
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG"
export PATH=\$PATH:/usr/sbin
cd src/tungstenfabric/tf-devstack/helm
ORCHESTRATOR=$ORCHESTRATOR ./run.sh platform
EOF

echo "INFO: Deploy platform finished"
