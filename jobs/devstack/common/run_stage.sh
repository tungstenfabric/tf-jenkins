#!/bin/bash -eE
set -o pipefail

deployer=$1
# can be empty which means default set of stages in tf-devstack
stage=$2

[ "${DEBUG,,}" == "true" ] && set -x

echo "INFO: Deploy $deployer/$stage ($JOB_NAME)"

cat <<EOF > $WORKSPACE/deploy_$stage.sh
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
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
export ENABLE_DPDK_SRIOV="$ENABLE_DPDK_SRIOV"
export ENABLE_NAGIOS=$ENABLE_NAGIOS
export LEGACY_ANALYTICS_ENABLE="$LEGACY_ANALYTICS_ENABLE"
export PATH=\$PATH:/usr/sbin
EOF

if declare -f -F add_deployrc &>/dev/null ; then
  add_deployrc $WORKSPACE/deploy_$stage.sh
fi

echo "src/tungstenfabric/tf-devstack/${deployer}/run.sh $stage" >> $WORKSPACE/deploy_$stage.sh
chmod a+x $WORKSPACE/deploy_$stage.sh

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/deploy_$stage.sh} $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./deploy_$stage.sh || res=1

echo "INFO: Deploy $stage finished"
exit $res
