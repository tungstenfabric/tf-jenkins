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
if [[ "$STAGE" == 'none' ]] && [[ ("$GERRIT_PIPELINE" != 'check' && "$GERRIT_PIPELINE" != 'templates') || "$GERRIT_BRANCH" != 'master' ]]; then
  # use frozen only for check pipeline
  unset DEVENV_TAG
fi

# transfer patchsets info into sandbox
if [ -e $WORKSPACE/patchsets-info.json ]; then
  mkdir -p $WORKSPACE/src/tungstenfabric/tf-dev-env/input/
  cp -f $WORKSPACE/patchsets-info.json $WORKSPACE/src/tungstenfabric/tf-dev-env/input/
fi

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS"

echo "INFO: Build started: ENVIRONMENT_OS=$ENVIRONMENT_OS LINUX_DISTR=$LINUX_DISTR"

export DEVENV_TAG=${DEVENV_TAG:-stable${TAG_SUFFIX}}
export BUILD_MODE="fast"
if grep -q "tungstenfabric/tf-dev-env" ./patchsets-info.json ; then
  # changes in tf-dev-env - we have to rebuild it
  export DEVENV_TAG="sandbox-$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
fi

# list for tf containers
mirror_list=""
# list of repos for building of tf-dev-sandbox container itself
mirror_list_for_build=""

if [[ ${LINUX_DISTR} == 'rhel7' ]]; then
  mirror_list_for_build="mirror-epel.repo google-chrome.repo mirror-rhel8-baseos.repo mirror-rhel8-archive.repo"
  mirror_list="google-chrome.repo"
elif [[ ${LINUX_DISTR} == 'centos' ]]; then
  mirror_list_for_build="mirror-epel.repo google-chrome.repo mirror-docker.repo mirror-base.repo "
  # epel must not be there - it cause incorrect installs and fails at runtime
  mirror_list="mirror-base.repo mirror-openstack.repo mirror-docker.repo google-chrome.repo"
  # add empty CentOS repos to disable them
  mirror_list_for_build+=" centos7/CentOS-Base.repo centos7/CentOS-CR.repo centos7/CentOS-Debuginfo.repo centos7/CentOS-Media.repo"
  mirror_list_for_build+=" centos7/CentOS-Sources.repo centos7/CentOS-Vault.repo centos7/CentOS-fasttrack.repo centos7/CentOS-x86_64-kernel.repo"
  mirror_list+=" centos7/CentOS-Base.repo centos7/CentOS-CR.repo centos7/CentOS-Debuginfo.repo centos7/CentOS-Media.repo"
  mirror_list+=" centos7/CentOS-Sources.repo centos7/CentOS-Vault.repo centos7/CentOS-fasttrack.repo centos7/CentOS-x86_64-kernel.repo"
elif [[ "${LINUX_DISTR}" =~ 'ubi7' ]] ; then
  mirror_list_for_build="mirror-epel.repo google-chrome.repo ubi.repo mirror-rhel7.repo mirror-rhel8-baseos.repo mirror-rhel8-archive.repo"
  mirror_list="google-chrome.repo ubi.repo mirror-rhel7.repo"
fi

if [[ $REPOS_CHANNEL != 'latest' ]]; then
  for repofile in $mirror_list_for_build $mirror_list; do
    sed -i "s|/latest/|/${REPOS_CHANNEL}/|g" ${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/${repofile}
  done
fi

# sync should be made after optional repo URLs updating
rsync -a -e "$ssh_cmd" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

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

export LINUX_DISTR=$LINUX_DISTR
export LINUX_DISTR_VER=${LINUX_DISTR_VER}
export SITE_MIRROR=$SITE_MIRROR
export GERRIT_URL=${GERRIT_URL}
export GERRIT_BRANCH=${GERRIT_BRANCH}
export GERRIT_PROJECT=${GERRIT_PROJECT}

# devenvtag is passed from parent job
export DEVENV_TAG=$DEVENV_TAG
export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX
export CONTRAIL_KEEP_LOG_FILES=true
export INSECURE_REGISTRIES=${INSECURE_REGISTRIES}
export MULTI_KERNEL_BUILD=true
export KERNEL_REPOSITORIES_RHEL8="--disablerepo=* --enablerepo=BaseOS --enablerepo=KERNELS_ARCHIVE_RHEL8"
export BUILD_MODE=$BUILD_MODE
export DEBUGINFO=$DEBUGINFO

cd src/tungstenfabric/tf-dev-env

# TODO: use in future generic mirror approach
# Copy yum repos for rhel from host to containers to use local mirrors

export BASE_EXTRA_RPMS=''
rm -rf ./config/etc
mkdir -p ./config/etc/yum.repos.d
case "${LINUX_DISTR}" in
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
  "centos")
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

mkdir -p ./config/etc/apt
cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/ubuntu18-sources.list ./config/etc/apt/sources.list

cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/mirror-pip.conf ./config/etc/pip.conf

sudo mkdir -p /etc/docker/
sudo cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/mirror-docker-daemon.json /etc/docker/daemon.json

echo "INFO: df -h"
df -h
echo "INFO: free -h"
free -h

./run.sh "$STAGE" "$TARGET"
EOF

if [[ "$res" != '0' ]] ; then
  echo "ERROR: Run failed. Stage: $STAGE  Target: $TARGET"
  exit $res
fi

rm -rf build.env
touch build.env
if [[ "$STAGE" == "fetch" ]]; then
  # after fetching sources we have to copy this file to publish it for UT
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
