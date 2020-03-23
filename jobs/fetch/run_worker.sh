#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

linux_distr=${TARGET_LINUX_DISTR["$ENVIRONMENT_OS"]}
tf_devenv_container_name="tf-developer-sandbox-${PIPELINE_BUILD_TAG}"
devenvtag=${DEVENVTAG:-stable${TAG_SUFFIX}}
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

export REGISTRY_IP=$REGISTRY_IP
export REGISTRY_PORT=$REGISTRY_PORT
export SITE_MIRROR=http://${REGISTRY_IP}/repository

# to not to bind contrail sources to container
export CONTRAIL_DIR=""

export BUILD_DEV_ENV=0
export BUILD_DEV_ENV_ON_PULL_FAIL=$build_dev_env
export LINUX_DISTR=$linux_distr
export TF_DEVENV_CONTAINER_NAME=$tf_devenv_container_name
export IMAGE=$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox
export DEVENVTAG=$devenvtag

cd src/tungstenfabric/tf-dev-env

# TODO: use in future generic mirror approach
# Copy yum repos for rhel from host to containers to use local mirrors

case "${ENVIRONMENT_OS}" in
  "rhel*")
    mkdir -p ./config/etc
    cp -r /etc/yum.repos.d ./config/etc/
    # TODO: now no way to pu gpg keys into containers for repo mirrors
    # disable gpgcheck as keys are not available inside the contianers
    find ./config/etc/yum.repos.d/ -name "*.repo" -exec sed -i 's/^gpgcheck.*/gpgcheck=0/g' {} + ;
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
    cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-docker.repo /etc/yum.repos.d/
    ;;
esac

./run.sh $stage
EOF
  echo "INFO: run tf-dev-env done: res=$res"
  return $res
}

function push_dev_env() {
  local tag=$1
  local target_tag="$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox:$tag"
  local res=0
  local commit_name="tf-developer-sandbox-$devenvtag"
  echo "INFO: Save container $target_tag"
  cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x
set -eo pipefail

echo "INFO: stop $tf_devenv_container_name container"
sudo docker stop $tf_devenv_container_name || true

echo "INFO: commit $tf_devenv_container_name container as $commit_name"
sudo docker commit $tf_devenv_container_name $commit_name

echo "INFO: tag $commit_name container as $target_tag"
sudo docker tag $commit_name $target_tag

echo "INFO: push $target_tag container"
sudo docker push $target_tag
EOF
  echo "INFO: Save container $target_tag done"
  return $res
}

# build stable
if [[ $res == 0 ]] ; then
  if run_dev_env none 1 ; then
    push_dev_env $devenvtag || res=1
  else
    res=1
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
