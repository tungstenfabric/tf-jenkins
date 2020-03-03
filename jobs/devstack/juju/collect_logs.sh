#!/bin/bash
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin
cd src/tungstenfabric/tf-devstack/juju
ORCHESTRATOR=$ORCHESTRATOR ./run.sh logs
EOF

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $IMAGE_SSH_USER@$instance_ip:logs.tgz $WORKSPACE/logs.tgz

pushd $WORKSPACE
tar -xzf logs.tgz
ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS $LOGS_HOST_USERNAME@$LOGS_HOST "mkdir -p $FULL_LOGS_PATH"
rsync -a -e "ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS" $WORKSPACE/logs $LOGS_HOST_USERNAME@$LOGS_HOST:$FULL_LOGS_PATH
rm -rf $WORKSPACE/logs
echo "INFO: Logs collected at ${LOGS_URL}/${JOB_LOGS_PATH}"
popd

exit $res
