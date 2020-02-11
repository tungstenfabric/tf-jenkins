#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

# do it as a latest source to override all exports
if [[ -f ${WORKSPACE}/build.env ]]; then
  source ${WORKSPACE}/build.env
fi

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

linux_distr=${TARGET_LINUX_DISTR["${ENVIRONMENT_OS}"]}

echo "INFO: Build started"

res=0
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin

# dont setup own registry
export CONTRAIL_DEPLOY_REGISTRY=0

export REGISTRY_IP=$REGISTRY_IP
export REGISTRY_PORT=$REGISTRY_PORT
export SITE_MIRROR=http://${REGISTRY_IP}/repository

export OPENSTACK_VERSIONS=rocky
export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG

# to not to bind contrail sources to container
export CONTRAIL_DIR=""

export IMAGE=$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox
export DEVENVTAG=$CONTRAIL_CONTAINER_TAG
export CONTRAIL_KEEP_LOG_FILES=true

export LINUX_DISTR=$linux_distr
export CONTRAIL_BUILD_FROM_SOURCE=${CONTRAIL_BUILD_FROM_SOURCE}

cd src/tungstenfabric/tf-dev-env

# TODO: use in future generic mirror approach
# Copy yum repos for rhel from host to containers to use local mirrors
if [[ "$linux_distr" =~ 'rhel' ]] ; then
  mkdir -p ./config/etc
  cp -r /etc/yum.repos.d ./config/etc/
fi

./run.sh build
EOF

if [[ "$res" != '0' ]] ; then
  echo "ERROR: Build failed"
  exit $res
fi
echo "INFO: Build finished successfully"
