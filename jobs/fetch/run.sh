#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

rsync -a -e "ssh $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: Fetch started"

cat <<EOF | ssh $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export PATH=\$PATH:/usr/sbin
export DEBUG=$DEBUG

# dont setup own registry
export CONTRAIL_DEPLOY_REGISTRY=0

# skip rpm repo at fetch stage
export CONTRAIL_DEPLOY_RPM_REPO=0

export REGISTRY_IP=$REGISTRY_IP
export REGISTRY_PORT=$REGISTRY_PORT
export SITE_MIRROR=http://${REGISTRY_IP}/repository

# TODO: enable later
# export CONTRAIL_BUILD_FROM_SOURCE=1

export OPENSTACK_VERSIONS=rocky
export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG

export GERRIT_CHANGE_ID=${GERRIT_CHANGE_ID}
export GERRIT_CHANGE_URL=${GERRIT_CHANGE_URL}
export GERRIT_BRANCH=${GERRIT_BRANCH}

# to not to bind contrail sources to container
export CONTRAIL_DIR=""

cd src/tungstenfabric/tf-dev-env
./run.sh fetch
EOF
result=$?
if [[ $result != 0 ]] ; then
  echo "ERROR: Fetch failed"
  exit $result
fi
echo "INFO: Fetch finished successfully"


target_name="tf-developer-sandbox-$CONTRAIL_CONTAINER_TAG"
target_tag="$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox:$CONTRAIL_CONTAINER_TAG"
echo "INFO: Save tf-sandbox started"
cat <<EOF | ssh $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x

echo "INFO: commit tf-developer-sandbox container"
if ! sudo docker commit tf-developer-sandbox $target_name ; then
  echo "ERROR: failed to commit tf-developer-sandbox"
  exit 1
fi

echo "INFO: tag tf-developer-sandbox container"
if ! sudo docker tag $target_name $target_tag ; then
  echo "ERROR: failed to tag container $target_tag"
  exit 1
fi

echo "INFO: push tf-developer-sandbox container"
if ! sudo docker push $target_tag ; then
  echo "ERROR: failed to push container $target_tag"
  exit 1
fi
EOF
result=$?
if [[ $result != 0 ]] ; then
  echo "ERROR: Save tf-sandbox failed"
  exit $result
fi
echo "INFO: Save tf-sandbox finished successfully"
