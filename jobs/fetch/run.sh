#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

# set to force devenv rebuild each time
export BUILD_DEV_ENV=${BUILD_DEV_ENV:-0}

function run_dev_env() {
  local stage=$1
  local devenv=$2
  local result=0
  cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || result=1
export WORKSPACE=\$HOME
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
export GERRIT_PROJECT=${GERRIT_PROJECT}
export GERRIT_CHANGE_NUMBER=${GERRIT_CHANGE_NUMBER}
export GERRIT_PATCHSET_NUMBER=${GERRIT_PATCHSET_NUMBER}

# to not to bind contrail sources to container
export CONTRAIL_DIR=""

export BUILD_DEV_ENV=$BUILD_DEV_ENV
export IMAGE=$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox
export DEVENVTAG=$devenv

cd src/tungstenfabric/tf-dev-env
./run.sh $stage
EOF
return $result
}

function push_dev_env() {
  local tag=$1
  local commit_name="tf-developer-sandbox-$tag"
  local target_tag="$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox:$tag"
  local result=0
  echo "INFO: Save tf-sandbox started: $target_tag"

  cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || result=1
export WORKSPACE=\$HOME
[ "${DEBUG,,}" == "true" ] && set -x

echo "INFO: commit tf-developer-sandbox container"
if ! sudo docker commit tf-developer-sandbox $commit_name ; then
  echo "ERROR: failed to commit tf-developer-sandbox"
  exit 1
fi

echo "INFO: tag tf-developer-sandbox container"
if ! sudo docker tag $commit_name $target_tag ; then
  echo "ERROR: failed to tag container $target_tag"
  exit 1
fi

echo "INFO: push tf-developer-sandbox container"
if ! sudo docker push $target_tag ; then
  echo "ERROR: failed to push container $target_tag"
  exit 1
fi
EOF
  return $result
}

echo "INFO: Build dev env"
if ! run_dev_env none stable ; then
  echo "ERROR: Build dev env failed"
  exit 1
fi
if ! push_dev_env stable ; then
  echo "ERROR: Save dev-env failed"
  exit 1
fi


echo "INFO: Sync started"
if ! run_dev_env "" stable ; then
  echo "ERROR: Sync failed"
  exit 1
fi
if ! push_dev_env $CONTRAIL_CONTAINER_TAG ; then
  echo "ERROR: Save tf-sandbox failed"
  exit 1
fi

echo "INFO: Fetch done"
