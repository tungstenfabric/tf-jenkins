#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: UT started"

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin

# dont setup own registry
export CONTRAIL_DEPLOY_REGISTRY=0

export REGISTRY_IP=$REGISTRY_IP
export REGISTRY_PORT=$REGISTRY_PORT
export SITE_MIRROR=http://${REGISTRY_IP}/repository

export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG

# to not to bind contrail sources to container
export CONTRAIL_DIR=""

export IMAGE=$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox
export DEVENVTAG=$CONTRAIL_CONTAINER_TAG

cd src/tungstenfabric/tf-dev-env
./run.sh test
tar -czvf /root/contrail/ut_logs.tgz $WORKSPACE/contrail/ut_logs/
EOF
result=$?

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $IMAGE_SSH_USER@$instance_ip:/root/tf-dev-env/ut_logs.tgz  $WORKSPACE/
mkdir -p $WORKSPACE/ut_logs/
tar -zxvf  $WORKSPACE/ut_logs.tgz -C $WORKSPACE/ut_logs/
rsync -a -e "ssh -i $ARCHIVE_SSH_KEY $SSH_OPTIONS" $WORKSPACE/ut_logs $ARCHIVE_USERNAME@$ARCHIVE_HOST:$FULL_LOGS_FILE_PATH || /bin/true

if [[ $result != 0 ]] ; then
  echo "ERROR: UT failed"
  exit $result
fi
echo "INFO: UT finished successfully"
