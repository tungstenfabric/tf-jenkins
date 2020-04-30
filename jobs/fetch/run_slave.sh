#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

function run_dev_env() {
  local stage=$1
  local build_dev_env=$2

  export CONTRAIL_SETUP_DOCKER=0
  export TF_CONFIG_DIR=$WORKSPACE

  # dont setup own registry
  export CONTRAIL_DEPLOY_REGISTRY=0
  # skip rpm repo at fetch stage
  export CONTRAIL_DEPLOY_RPM_REPO=0

  export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX

  # to not to bind contrail sources to container
  export CONTRAIL_DIR=""

  # disable build dev-env
  export BUILD_DEV_ENV=$build_dev_env
  export BUILD_DEV_ENV_ON_PULL_FAIL=0

  # all other variables already exported

  # use root user because slave is ubuntu but build machine is centos
  # and they have different users
  export DEVENV_USER=root
  cd $WORKSPACE/src/tungstenfabric/tf-dev-env
  ./run.sh $stage
}

function push_dev_env() {
  export DEVENV_PUSH_TAG=$1

  export TF_CONFIG_DIR=$WORKSPACE
  # dont setup own registry
  export CONTRAIL_DEPLOY_REGISTRY=0
  # skip rpm repo at fetch stage
  export CONTRAIL_DEPLOY_RPM_REPO=0

  # use root user because slave is ubuntu but build machine is centos
  # and they have different users
  export DEVENV_USER=root
  cd $WORKSPACE/src/tungstenfabric/tf-dev-env
  ./run.sh upload
}

etc_dir="$WORKSPACE/src/tungstenfabric/tf-dev-env/config/etc"
mkdir -p $etc_dir/yum.repos.d
cp ${my_dir}/../../infra/mirrors/mirror-pip.conf $etc_dir/pip.conf
if [[ "${ENVIRONMENT_OS,,}" == 'centos7' ]]; then
  cp ${my_dir}/../../infra/mirrors/mirror-base.repo $etc_dir/yum.repos.d/
  cp ${my_dir}/../../infra/mirrors/mirror-epel.repo $etc_dir/yum.repos.d/
fi

if [[ $BUILD_DEV_ENV == 1 ]] || ! sudo docker pull "$CONTAINER_REGISTRY/$DEVENV_IMAGE_NAME:$DEVENV_TAG" ; then
  if ! run_dev_env none 1 ; then
    echo "ERROR: Sync failed"
    exit 1
  fi
  if ! push_dev_env $DEVENV_TAG ; then
    echo "ERROR: Save tf-sandbox failed"
    exit 1
  fi
fi

echo "INFO: Sync started"

if ! run_dev_env "" 0 ; then
  echo "ERROR: Sync failed"
  exit 1
fi
if ! push_dev_env $CONTRAIL_CONTAINER_TAG$TAG_SUFFIX ; then
  echo "ERROR: Save tf-sandbox failed"
  exit 1
fi

# to collect as artefact
cp -f $WORKSPACE/output/unittest_targets.lst $WORKSPACE/unittest_targets.lst

echo "INFO: Fetch done"
