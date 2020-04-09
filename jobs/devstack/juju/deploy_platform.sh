#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

echo "INFO: Deploy platform for $JOB_NAME"
rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

bash -c "\
ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS $IMAGE_SSH_USER@$instance_ip \
[ "${DEBUG,,}" == "true" ] && set -x; \
export WORKSPACE=\$HOME; \
export DEBUG=$DEBUG; \
export OPENSTACK_VERSION=$OPENSTACK_VERSION; \
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"; \
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"; \
export CLOUD=${CLOUD:-"local"}; \
source \$HOME/$CLOUD.vars || /bin/true; \
export PATH=\$PATH:/usr/sbin; \
cd \$HOME/src/tungstenfabric/tf-devstack/juju; \
ORCHESTRATOR=$ORCHESTRATOR ./run.sh platform" || ret=1

echo "INFO: Deploy platform finished"
exit $ret


