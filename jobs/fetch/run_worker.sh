#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

linux_distr=${TARGET_LINUX_DISTR["$ENVIRONMENT_OS"]}
#TODO: Rebuild be done only for review for dev-env,
# re-tagging for stable will be done only after successful tests
$WORKSPACE/src/progmaticlab/tf-jenkins/infra/${SLAVE}/create_workers.sh
# source env right after creation
source "$WORKSPACE/stackrc.$JOB_NAME.env"

res=0
rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./ || res=1

function run_dev_env() {
  local stage=$1
  local build_dev_env=$2
  local res=0
  echo "INFO: run tf-dev-env started..."
  cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x

export WORKSPACE=\$HOME
export TF_CONFIG_DIR=\$HOME

# dont setup own registry & repo
export CONTRAIL_DEPLOY_REGISTRY=0
export CONTRAIL_DEPLOY_RPM_REPO=0

export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
export SITE_MIRROR=$SITE_MIRROR

export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX

export GERRIT_URL=${GERRIT_URL}
export GERRIT_BRANCH=${GERRIT_BRANCH}

# to not to bind contrail sources to container
export CONTRAIL_DIR=""

export BUILD_DEV_ENV=$build_dev_env
export BUILD_DEV_ENV_ON_PULL_FAIL=0
export LINUX_DISTR=$linux_distr
export DEVENV_CONTAINER_NAME=$DEVENV_CONTAINER_NAME
export DEVENV_IMAGE_NAME=$DEVENV_IMAGE_NAME
export DEVENV_TAG=$DEVENV_TAG

cd src/tungstenfabric/tf-dev-env

# TODO: use in future generic mirror approach
# Copy yum repos for rhel from host to containers to use local mirrors

case "${ENVIRONMENT_OS}" in
  "rhel7")
    export BASE_EXTRA_RPMS=''
    export RHEL_HOST_REPOS=''
    mkdir -p ./config/etc
    cp -r /etc/yum.repos.d ./config/etc/
    # TODO: now no way to pu gpg keys into containers for repo mirrors
    # disable gpgcheck as keys are not available inside the contianers
    find ./config/etc/yum.repos.d/ -name "*.repo" -exec sed -i 's/^gpgcheck.*/gpgcheck=0/g' {} + ;
    cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-pip.conf ./config/etc/pip.conf
    ;;
  "centos7")
    # TODO: think how to copy only required repos and disable default repos
    # - host has centos7/epel enabled. but we also need to copy chrome/docker/openstack repos
    # but these repos are not needed for rhel
    mkdir -p ./config/etc/yum.repos.d
    cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-base.repo ./config/etc/yum.repos.d/
    cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-epel.repo ./config/etc/yum.repos.d/
    cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-pip.conf ./config/etc/pip.conf
    # copy docker repo to local machine
    sudo cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-docker.repo /etc/yum.repos.d/
    # use root user for because slave is ubuntu but build machine is centos
    # and they have different users
    export DEVENV_USER=root
    ;;
esac

./run.sh $stage
EOF
  echo "INFO: run tf-dev-env done: res=$res"
  return $res
}

function push_dev_env() {
  local tag=$1
  local res=0
  echo "INFO: Save container to registry"
  cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x
set -eo pipefail

export DEVENV_PUSH_TAG=$tag
export DEVENV_IMAGE_NAME=$DEVENV_IMAGE_NAME
export DEVENV_CONTAINER_NAME=$DEVENV_CONTAINER_NAME
export CONTAINER_REGISTRY=$CONTAINER_REGISTRY

export WORKSPACE=\$HOME
export TF_CONFIG_DIR=\$HOME

# dont setup own registry & repo
export CONTRAIL_DEPLOY_REGISTRY=0
export CONTRAIL_DEPLOY_RPM_REPO=0

export DEVENV_USER=root
cd src/tungstenfabric/tf-dev-env
./run.sh upload
EOF
  echo "INFO: Saving of container is done"
  return $res
}

function has_image() {
  local tags=$(curl -s --show-error http://${CONTAINER_REGISTRY}/v2/${DEVENV_IMAGE_NAME}/tags/list | jq -c -r '.tags[]')
  echo "INFO: looking for a tag $DEVENV_TAG in found tags for tf-developer-sandbox:"
  echo "$tags" | sort
  echo "$tags" | grep -q "^${DEVENV_TAG}\$"
}

# build stable
if [[ $res == 0 ]] ; then
  if [[ $BUILD_DEV_ENV == 1 ]] || ! has_image ; then
    if run_dev_env none 1 ; then
      push_dev_env $DEVENV_TAG || res=1
    else
      res=1
    fi
  fi
fi

# sync & configure
if [[ $res == 0 ]] ; then
  if run_dev_env "" 0 ; then
    push_dev_env $CONTRAIL_CONTAINER_TAG$TAG_SUFFIX || res=1
  else
    res=1
  fi
fi

# remove worker as soon as possible to free resources
if ! $WORKSPACE/src/progmaticlab/tf-jenkins/infra/${SLAVE}/remove_workers.sh ; then
  echo "WARNING: failed to delete worker... it be cleanuped by GC tasks later"
fi

exit $res
