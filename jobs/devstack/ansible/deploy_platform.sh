#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

echo "INFO: Deploy platform for $JOB_NAME"

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS $IMAGE_SSH_USER@$instance_ip \
    [ "${DEBUG,,}" == "true" ] && set -x; \
    export WORKSPACE=\$HOME; \
    export DEBUG=$DEBUG; \
    export OPENSTACK_VERSION=$OPENSTACK_VERSION; \
    export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"; \
    export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"; \
    export PATH=\$PATH:/usr/sbin; \
    cd src/tungstenfabric/tf-devstack/ansible; \
    ORCHESTRATOR=$ORCHESTRATOR; \
    "./run.sh platform" || res=1

#cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
#[ "${DEBUG,,}" == "true" ] && set -x
#export WORKSPACE=\$HOME
#export DEBUG=$DEBUG
#export OPENSTACK_VERSION=$OPENSTACK_VERSION
#export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
#export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
#export PATH=\$PATH:/usr/sbin
#cd src/tungstenfabric/tf-devstack/ansible
#ORCHESTRATOR=$ORCHESTRATOR ./run.sh platform
#EOF

echo "INFO: Deploy platform finished"
exit $res
