#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: Build started"

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

# TODO: enable later
# export CONTRAIL_BUILD_FROM_SOURCE=1

export OPENSTACK_VERSIONS=rocky
export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG

# to not to bind contrail sources to container
export CONTRAIL_DIR=""

export IMAGE=$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox
export DEVENVTAG=$CONTRAIL_CONTAINER_TAG
export CONTRAIL_KEEP_LOG_FILES=true

cd src/tungstenfabric/tf-dev-env
./run.sh build
EOF

result=$?
if [[ $result != 0 ]] ; then
  echo "ERROR: Build failed"
  exit $result
fi
echo "INFO: Build finished successfully"


cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin


sudo docker cp tf-developer-sandbox:/root/contrail/contrail-container-builder/containers .
sudo find ./containers/ -not -name '*.log' -delete &>/dev/null || /bin/true
tar -czf containers.tgz containers
sudo rm -rf ./containers
EOF

rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" ${IMAGE_SSH_USER}@${instance_ip}:containers.tgz ${WORKSPACE}/
tar -zxvf  ${WORKSPACE}/containers.tgz

ssh -i ${LOGS_HOST_SSH_KEY} ${SSH_OPTIONS} ${LOGS_HOST_USERNAME}@${LOGS_HOST} "mkdir -p ${FULL_LOGS_PATH}"
rsync -a -e "ssh -i ${LOGS_HOST_SSH_KEY} ${SSH_OPTIONS}" ${WORKSPACE}/containers ${LOGS_HOST_USERNAME}@${LOGS_HOST}:${FULL_LOGS_PATH} || /bin/true
