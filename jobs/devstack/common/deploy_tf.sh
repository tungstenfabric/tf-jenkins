#!/bin/bash -eE
set -o pipefail

deployer=$1

set -x

echo "INFO: Deploy TF with $deployer"

cat <<EOF > $WORKSPACE/deploy_tf.sh
#!/bin/bash -e
set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export ORCHESTRATOR=$ORCHESTRATOR
export OPENSTACK_VERSION=$OPENSTACK_VERSION
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export DEPLOYER_CONTAINER_REGISTRY="$DEPLOYER_CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export CONTRAIL_DEPLOYER_CONTAINER_TAG="$CONTRAIL_DEPLOYER_CONTAINER_TAG$TAG_SUFFIX"
export SSL_ENABLE=$SSL_ENABLE
export CONTROLLER_NODES="$CONTROLLER_NODES"
export AGENT_NODES="$AGENT_NODES"
export PATH=\$PATH:/usr/sbin
EOF

if declare -f -F add_deployrc &>/dev/null ; then
  add_deployrc $WORKSPACE/deploy_tf.sh
fi

echo "src/tungstenfabric/tf-devstack/${deployer}/run.sh" >> $WORKSPACE/deploy_tf.sh
chmod a+x $WORKSPACE/deploy_tf.sh

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/deploy_tf.sh} $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./deploy_tf.sh || res=1

echo "INFO: Deploy TF finished"
exit $res
