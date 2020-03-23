#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

export TF_DEVENV_CONTAINER_NAME="tf-developer-sandbox-${PIPELINE_BUILD_TAG}"
devenvtag=${DEVENVTAG:-stable${TAG_SUFFIX}}
container_tag=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX

function run_dev_env() {
  local stage=$1
  local build_dev_env=$2

  export CONTRAIL_SETUP_DOCKER=0
  export TF_CONFIG_DIR=$WORKSPACE

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
  export CONTRAIL_CONTAINER_TAG=$container_tag

  export GERRIT_CHANGE_ID=${GERRIT_CHANGE_ID}
  export GERRIT_URL=${GERRIT_URL}
  export GERRIT_BRANCH=${GERRIT_BRANCH}

  # to not to bind contrail sources to container
  export CONTRAIL_DIR=""

  # disable build dev-env
  export BUILD_DEV_ENV=$build_dev_env
  export BUILD_DEV_ENV_ON_PULL_FAIL=0
  export IMAGE=$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox
  export DEVENVTAG=$devenvtag

  cd $WORKSPACE/src/tungstenfabric/tf-dev-env
  ./run.sh $stage
}

function push_dev_env() {
  local tag=$1
  local commit_name="tf-developer-sandbox-$tag"
  local target_tag="$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox:$tag"

  echo "INFO: Save tf-sandbox started: $target_tag"
  echo "INFO: stop tf-developer-sandbox container"
  sudo docker stop $TF_DEVENV_CONTAINER_NAME || true

  echo "INFO: commit tf-developer-sandbox container"
  if ! sudo docker commit $TF_DEVENV_CONTAINER_NAME $commit_name ; then
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
}

if [[ "${ENVIRONMENT_OS,,}" == 'centos7' ]]; then
  etc_dir="$WORKSPACE/src/tungstenfabric/tf-dev-env/config/etc"
  mkdir -p $etc_dir/yum.repos.d
  cp ${my_dir}/../../infra/mirrors/mirror-base.repo $etc_dir/yum.repos.d/
  cp ${my_dir}/../../infra/mirrors/mirror-epel.repo $etc_dir/yum.repos.d/
  cp ${my_dir}/../../infra/mirrors/mirror-pip.conf $etc_dir/pip.conf
fi

if ! sudo docker pull "$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox:$devenvtag" ; then
  if ! run_dev_env none 1 ; then
    echo "ERROR: Sync failed"
    exit 1
  fi
  if ! push_dev_env $devenvtag ; then
    echo "ERROR: Save tf-sandbox failed"
    exit 1
  fi
fi

echo "INFO: Sync started"

if ! run_dev_env "" 0 ; then
  echo "ERROR: Sync failed"
  exit 1
fi
if ! push_dev_env $container_tag ; then
  echo "ERROR: Save tf-sandbox failed"
  exit 1
fi

echo "INFO: Fetch done"
