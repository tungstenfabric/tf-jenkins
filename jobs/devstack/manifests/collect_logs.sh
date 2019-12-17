#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

ENV_FILE=${ENV_FILE:-"$WORKSPACE/stackrc.$JOB_NAME.env"}
source $ENV_FILE

source "$my_dir/definitions"

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin
echo INFO: Sanity logs path content
ls -la /home/centos/src/tungstenfabric/tf-test/contrail-sanity/contrail-test-runs/ || /bin/true
cd src/tungstenfabric/tf-devstack/k8s_manifests
ORCHESTRATOR=$ORCHESTRATOR ./run.sh logs
EOF

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $IMAGE_SSH_USER@$instance_ip:logs.tgz $WORKSPACE/logs.tgz

pushd $WORKSPACE
tar -xzf logs.tgz FULL_LOGS_PATH="${LOGS_PATH}/${JOB_LOGS_PATH}"
ls -la
ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS $LOGS_HOST_USERNAME@$LOGS_HOST "mkdir -p $FULL_LOGS_PATH"
rsync -a -e "ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS" $WORKSPACE/logs $LOGS_HOST_USERNAME@$LOGS_HOST:$FULL_LOGS_PATH
rm -rf $WORKSPACE/logs
echo "INFO: Logs collected at ${LOGS_URL}/${JOB_LOGS_PATH}"
popd
