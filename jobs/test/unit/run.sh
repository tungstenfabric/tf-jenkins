#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

# transfer unittest targets info into sandbox
if [ -e $WORKSPACE/unittest_targets.lst ]; then
  mkdir -p $WORKSPACE/src/tungstenfabric/tf-dev-env/input/
  cp -f $WORKSPACE/unittest_targets.lst $WORKSPACE/src/tungstenfabric/tf-dev-env/input/
fi
echo $TARGET_SET > $WORKSPACE/src/tungstenfabric/tf-dev-env/input/target_set

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

# devenftag is passed from parent fetch-sources job
export DEVENV_TAG=$DEVENV_TAG
export DEVENV_PUSH_TAG=$DEVENV_TAG$DEVENV_PUSH_TAG

# Some tests (like test.test_flow.FlowQuerierTest.test_1_noarg_query) expect
# PST timezone, and fail otherwise.
timedatectl
sudo timedatectl set-timezone America/Los_Angeles
timedatectl

cd src/tungstenfabric/tf-dev-env
# TODO: unify this with build/run.sh

mkdir -p ./config/etc/yum.repos.d
cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/mirror-pip.conf ./config/etc/pip.conf
# substitute repos only for centos7
if [[ "${ENVIRONMENT_OS,,}" == 'centos7' ]]; then
  cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/mirror-base.repo ./config/etc/yum.repos.d/
  # copy base & docker repo to local machine
  sudo cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/mirror-base.repo /etc/yum.repos.d/
  sudo cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/mirror-docker.repo /etc/yum.repos.d/
fi
./run.sh $@
EOF
return $res
}

if ! run_over_ssh $STAGE $TARGET ; then
  echo "ERROR: UT failed"
  exit 1
fi

# DEVENV_PUSH_TAG is just a suffix here for final tag
# it was used for 'compile' job that is not present now
if [[ -n "$DEVENV_PUSH_TAG" ]]; then
  if ! run_over_ssh upload ; then
    echo "ERROR: push to registry with tag=$DEVENV_PUSH_TAG failed"
    exit 1
  fi
  # save DEVENV_TAG that is pushed by this job
  echo "export DEVENV_TAG=$DEVENV_TAG$DEVENV_PUSH_TAG" > testunit.env
fi

echo "INFO: UT finished successfully"
