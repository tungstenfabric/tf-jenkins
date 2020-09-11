#!/bin/bash
set -o pipefail

deployer=$1

[ "${DEBUG,,}" == "true" ] && set -x

cat <<EOF > $WORKSPACE/collect_logs.sh
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export ORCHESTRATOR=$ORCHESTRATOR
export SSL_ENABLE=$SSL_ENABLE
export CONTROLLER_NODES="$CONTROLLER_NODES"
export AGENT_NODES="$AGENT_NODES"
export PATH=\$PATH:/usr/sbin
EOF

if declare -f -F add_deployrc &>/dev/null ; then
  add_deployrc $WORKSPACE/collect_logs.sh
fi

cat <<EOF >> $WORKSPACE/collect_logs.sh
./src/tungstenfabric/tf-devstack/${deployer}/run.sh logs
EOF

chmod a+x $WORKSPACE/collect_logs.sh

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" $WORKSPACE/collect_logs.sh $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./collect_logs.sh || res=1
rsync -a -e "$ssh_cmd" $IMAGE_SSH_USER@$instance_ip:logs.tgz $WORKSPACE/logs.tgz

pushd $WORKSPACE
tar -xzf logs.tgz
ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS $LOGS_HOST_USERNAME@$LOGS_HOST "mkdir -p $FULL_LOGS_PATH"
rsync -a -e "ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS" $WORKSPACE/logs $LOGS_HOST_USERNAME@$LOGS_HOST:$FULL_LOGS_PATH
rm -rf $WORKSPACE/logs
echo "INFO: Logs collected at ${LOGS_URL}/${JOB_LOGS_PATH}"
popd

exit $res
