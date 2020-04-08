#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

CLOUD=${CLOUD:-"local"}

echo "INFO: Deploy platform for $JOB_NAME"
rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

bash -c "\
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
if [ "$CLOUD" == "maas" ]; then
cd \$HOME/src/tungstenfabric/tf-devstack/common
IPMI_IPS='192.168.51.20 192.168.51.21 192.168.51.22 192.168.51.23 192.168.51.24' ./deploy_maas.sh | grep ^export > \$HOME/maas.vars
source \$HOME/maas.vars
fi
export OPENSTACK_VERSION=$OPENSTACK_VERSION
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export CLOUD=$CLOUD
export PATH=\$PATH:/usr/sbin
cd \$HOME/src/tungstenfabric/tf-devstack/juju
ORCHESTRATOR=$ORCHESTRATOR ./run.sh platform
EOF" || res=1

echo "INFO: Deploy platform finished"
exit $res"
