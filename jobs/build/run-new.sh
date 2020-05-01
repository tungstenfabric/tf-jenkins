#!/bin/bash -eE
set -o pipefail

set -x
[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

# transfer patchsets info into sandbox
if [ -e $WORKSPACE/patchsets-info.json ]; then
  mkdir -p $WORKSPACE/src/tungstenfabric/tf-dev-env/input/
  cp -f $WORKSPACE/patchsets-info.json $WORKSPACE/src/tungstenfabric/tf-dev-env/input/
fi

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS"
rsync -a -e "$ssh_cmd" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

linux_distr=${TARGET_LINUX_DISTR["${ENVIRONMENT_OS}"]}

echo "INFO: Build started"

export DEVENV_TAG=${DEVENV_TAG:-stable${TAG_SUFFIX}}
if grep -q "tungstenfabric/tf-dev-env" ./patchsets-info.json ; then
  # changes in tf-dev-env - we have to rebuild it
  export DEVENV_TAG="sandbox-$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
fi

# build queens for test container always and add OPENSTACK_VERSION if it's different
openstack_versions='queens'
if [[ "$OPENSTACK_VERSION" != 'queens' ]]; then
  openstack_versions+=",$OPENSTACK_VERSION"
fi

res=0
cat <<EOF | $ssh_cmd $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin

export WORKSPACE=\$HOME
# dont setup own registry
export CONTRAIL_DEPLOY_REGISTRY=0
# to not to bind contrail sources to container
export CONTRAIL_DIR=""

export LINUX_DISTR=$linux_distr
export SITE_MIRROR=$SITE_MIRROR
export GERRIT_URL=${GERRIT_URL}
export GERRIT_BRANCH=${GERRIT_BRANCH}

# devenftag is passed from parent job
export DEVENV_TAG=$DEVENV_TAG
export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX
export OPENSTACK_VERSIONS=$openstack_versions
export CONTRAIL_BUILD_FROM_SOURCE=${CONTRAIL_BUILD_FROM_SOURCE}
export CONTRAIL_KEEP_LOG_FILES=true

# for the first stage prepare-stable
export BUILD_DEV_ENV=1
export BUILD_DEV_ENV_ON_PULL_FAIL=0

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
    cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-google-chrome.repo ./config/etc/yum.repos.d/
    cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-pip.conf ./config/etc/pip.conf
    ;;
  "centos7")
    # TODO: think how to copy only required repos
    # - host has centos7/epel enabled. but we also need to copy chrome/docker/openstack repos
    # but these repos are not needed for rhel
    mkdir -p ./config/etc/yum.repos.d
    cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-base.repo ./config/etc/yum.repos.d/
    cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-google-chrome.repo ./config/etc/yum.repos.d/
    cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-openstack.repo ./config/etc/yum.repos.d/
    cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-pip.conf ./config/etc/pip.conf
    # copy docker repo to local machine
    sudo cp \${WORKSPACE}/src/progmaticlab/tf-jenkins/infra/mirrors/mirror-docker.repo /etc/yum.repos.d/
    # use root user for because slave is ubuntu but build machine is centos
    # and they have different users
    export DEVENV_USER=root
    ;;
esac

./run.sh "$STAGE" "$TARGET"
EOF

if [[ "$res" != '0' ]] ; then
  echo "ERROR: Run failed. Stage: $STAGE  Target: $TARGET"
  exit $res
fi

rm -rf build.env
touch build.env
if [[ -z "$STAGE" ]]; then
  # default stage meams sync sources. after sync we have to copy this file to publish it for UT
  rsync -a -e "$ssh_cmd" $IMAGE_SSH_USER@$instance_ip:output/unittest_targets.lst $WORKSPACE/unittest_targets.lst || res=1
  echo "export UNITTEST_TARGETS=$(cat $WORKSPACE/unittest_targets.lst | tr '\n' ',')" >> fetch.env
fi

if [[ -n "$PUBLISH" ]]; then
  tag="$PUBLISH$TAG_SUFFIX"
  if [[ "$tag" == 'build' ]];
    tag="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
  fi
  cat <<EOF | $ssh_cmd $IMAGE_SSH_USER@$instance_ip || res=1
set -eo pipefail
export WORKSPACE=\$HOME
export DEVENV_PUSH_TAG=$tag
export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
src/tungstenfabric/tf-dev-env/run.sh upload
EOF

  if [[ "$res" != '0' ]] ; then
    echo "ERROR: Publish failed for tag $tag. Stage: $STAGE  Target: $TARGET"
    exit $res
  fi

  # save DEVENV_TAG that was pushed by this job
  # chidlren jobs may have own TAG_SUFFIX and they shouldn't rely on it
  echo "export DEVENV_TAG=$tag" > build.env
fi

echo "INFO: Build finished successfully"
