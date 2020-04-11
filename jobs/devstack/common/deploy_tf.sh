#!/bin/bash -eE
set -o pipefail

deployer=$1

[ "${DEBUG,,}" == "true" ] && set -x

echo "INFO: Deploy TF with $deployer"

cat <<EOF > $WORKSPACE/deployrc
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export ORCHESTRATOR=$ORCHESTRATOR
export OPENSTACK_VERSION=$OPENSTACK_VERSION
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export PATH=\$PATH:/usr/sbin
EOF

if declare -f -F add_deployrc &>/dev/null ; then
  add_deployrc
fi

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/deployrc} $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip "source deployrc ; src/tungstenfabric/tf-devstack/${deployer}/run.sh" || res=1

echo "INFO: Deploy TF finished"
exit $res
