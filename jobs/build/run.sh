#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

rsync -a -e "ssh $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: Build started"

cat <<EOF | ssh $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin
export IMAGE=tf-dev-env
export DEVENVTAG="master"
#export CONTRAIL_BUILD_FROM_SOURCE=1
export CONTRAIL_CONTAINER_TAG="$PATCHSET_ID"
export OPENSTACK_VERSIONS="rocky"
#export OPENSTACK_VERSIONS="ocata,queens,rocky"
#export SRC_ROOT="{{ ansible_env.HOME }}/{{ packaging.target_dir }}"
#export EXTERNAL_REPOS="{{ ansible_env.HOME }}/src"
#export CANONICAL_HOSTNAME="{{ zuul.project.canonical_hostname }}"
export REGISTRY_IP="pnexus.sytes.net"
export REGISTRY_PORT="5001"
export SITE_MIRROR="http://pnexus.sytes.net/repository"

cd src/tungstenfabric/tf-dev-env
./run.sh build
EOF

echo "INFO: Build finished"
