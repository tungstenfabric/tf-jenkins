#!/bin/bash -eE
set -o pipefail

deployer=$1

[ "${DEBUG,,}" == "true" ] && set -x

echo "INFO: Deploy platform for $JOB_NAME"

cat <<EOF > $WORKSPACE/deploy_platform.sh
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export ORCHESTRATOR=$ORCHESTRATOR
export OPENSTACK_VERSION=$OPENSTACK_VERSION
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export DEPLOYER_CONTAINER_REGISTRY="$DEPLOYER_CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export DEPLOYER_CONTRAIL_CONTAINER_TAG="$DEPLOYER_CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export SSL_ENABLE=$SSL_ENABLE
export CONTROLLER_NODES="$CONTROLLER_NODES"
export AGENT_NODES="$AGENT_NODES"
export PATH=\$PATH:/usr/sbin
EOF

if declare -f -F add_deployrc &>/dev/null ; then
  add_deployrc $WORKSPACE/deploy_platform.sh
fi

echo "src/tungstenfabric/tf-devstack/${deployer}/run.sh platform" >> $WORKSPACE/deploy_platform.sh
chmod a+x $WORKSPACE/deploy_platform.sh

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/deploy_platform.sh} $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./deploy_platform.sh || res=1

echo "INFO: Deploy platform finished"
exit $res
