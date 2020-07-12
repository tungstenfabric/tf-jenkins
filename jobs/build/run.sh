#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

if [[ "$STAGE" == 'freeze' ]] && [[ "$GERRIT_PIPELINE" != 'gate' || "$GERRIT_BRANCH" != 'master' ]]; then
  echo "INFO: Freeze works only for gate pipeline and for master branch"
  exit
fi
if [[ "$STAGE" == 'none' && "$GERRIT_PIPELINE" != 'check' ]]; then
  # use frozen only for check pipeline
  unset DEVENV_TAG
fi

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

if [[ ${ENVIRONMENT_OS} == 'rhel7' ]]; then
  mirror_list_for_build="mirror-epel.repo mirror-google-chrome.repo mirror-rhel8-baseos.repo"
elif [[ ${ENVIRONMENT_OS} == 'centos7' ]]; then
  mirror_list_for_build="mirror-base.repo mirror-epel.repo mirror-docker.repo mirror-google-chrome.repo"
fi

mirror_list=""
# epel must not be there - it cause incorrect installs and fails at runtime
if [[ ${ENVIRONMENT_OS} == 'centos7' ]]; then
  mirror_list="mirror-base.repo mirror-openstack.repo mirror-docker.repo"
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
export LINUX_DISTR_VER=${LINUX_DISTR_VER}
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

export MULTI_KERNEL_BUILD=true

cd src/tungstenfabric/tf-dev-env

# TODO: use in future generic mirror approach
# Copy yum repos for rhel from host to containers to use local mirrors

export BASE_EXTRA_RPMS=''
rm -rf ./config/etc
mkdir -p ./config/etc/yum.repos.d
case "${ENVIRONMENT_OS}" in
  "rhel7")
    export RHEL_HOST_REPOS=''
    # TODO: now no way to put gpg keys into containers for repo mirrors
    # disable gpgcheck as keys are not available inside the contianers
    for frepo in \$(find /etc/yum.repos.d/ -name "*.repo" -printf "%P\\n") ; do
      cp -f /etc/yum.repos.d/\$frepo ./config/etc/yum.repos.d/
      sed -i 's/^gpgcheck.*/gpgcheck=0/g' ./config/etc/yum.repos.d/\$frepo
      cp -f ./config/etc/yum.repos.d/\$frepo ./container/\$frepo
    done
    ;;
  "centos7")
    # copy docker repo to local machine
    sudo cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/mirror-docker.repo /etc/yum.repos.d/
    ;;
esac
for mirror in $mirror_list_for_build ; do
  cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/\$mirror ./container/
done
for mirror in $mirror_list ; do
  cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/\$mirror ./config/etc/yum.repos.d/
done
cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/mirror-pip.conf ./config/etc/pip.conf

echo "INFO: df -h"
df -h
echo "INFO: free -h"
free -h

if [[ -n "$STAGE" ]]; then
  ./run.sh "$STAGE" "$TARGET"
else
  # default stage marked as finished in frozen image - call stages explicitly
  ./run.sh fetch
  ./run.sh configure
fi
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
  echo "export UNITTEST_TARGETS=$(cat $WORKSPACE/unittest_targets.lst | tr '\n' ',')" >> build.env
fi

if [[ -n "$PUBLISH_TYPE" ]]; then
  if [[ "$PUBLISH_TYPE" == 'stable' ]]; then
    tag="$DEVENV_TAG"
  elif [[ "$PUBLISH_TYPE" == 'build' ]]; then
    tag="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
  elif [[ "$PUBLISH_TYPE" == 'frozen' ]]; then
    tag="frozen$TAG_SUFFIX"
  else
    echo "ERROR: unsupported publish type: $PUBLISH_TYPE"
    exit 1
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
  echo "export DEVENV_TAG=$tag" >> build.env
fi

echo "INFO: Build finished successfully"
