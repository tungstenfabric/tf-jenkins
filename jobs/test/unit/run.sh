#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

STAGE=${STAGE:-test}

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: UT started"

function run_over_ssh() {
  res=0
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin

# dont setup own registry
export CONTRAIL_DEPLOY_REGISTRY=0

export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
export SITE_MIRROR=$SITE_MIRROR

export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX

# to not to bind contrail sources to container
export CONTRAIL_DIR=""

export DEVENV_IMAGE_NAME=$CONTAINER_REGISTRY/tf-developer-sandbox
# devenftag is passed from parent fetch-sources job
export DEVENV_TAG=$DEVENV_TAG

# Some tests (like test.test_flow.FlowQuerierTest.test_1_noarg_query) expect
# PST timezone, and fail otherwise.
timedatectl
sudo timedatectl set-timezone America/Los_Angeles
timedatectl

cd src/tungstenfabric/tf-dev-env
# TODO: unify this with build/run.sh

mkdir -p ./config/etc/yum.repos.d
cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-pip.conf ./config/etc/pip.conf
# substitute repos only for centos7
if [[ "${ENVIRONMENT_OS,,}" == 'centos7' ]]; then
  cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-base.repo ./config/etc/yum.repos.d/
  cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-openstack.repo ./config/etc/yum.repos.d/
  # copy docker repo to local machine
  sudo cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-docker.repo /etc/yum.repos.d/
  # use root user for because slave is ubuntu but build machine is centos
  # and they have different users
  export DEVENV_USER=root
fi
./run.sh $@
EOF
return $res
}

if ! run_over_ssh ; then
  echo "ERROR: UT failed"
  exit 1
fi
if ! run_over_ssh $STAGE $TARGET ; then
  echo "ERROR: UT failed"
  exit 1
fi

echo "INFO: UT finished successfully"
