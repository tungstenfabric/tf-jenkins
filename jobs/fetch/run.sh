#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

rsync -a -e "ssh $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: Fetch started"

cat <<EOF | ssh $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export PATH=\$PATH:/usr/sbin
export DEBUG=$DEBUG
# export CONTRAIL_BUILD_FROM_SOURCE=1
# export CANONICAL_HOSTNAME="{{ zuul.project.canonical_hostname }}"
export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG
export OPENSTACK_VERSIONS="rocky"
export REGISTRY_IP="pnexus.sytes.net"
export REGISTRY_PORT="5001"
export SITE_MIRROR="http://pnexus.sytes.net/repository"
# to not to bind contrail sources to container
export CONTRAIL_DIR=""

cd src/tungstenfabric/tf-dev-env
./run.sh fetch || exit 1

target_name="tf-developer-sandbox-$CONTRAIL_CONTAINER_TAG"
sudo docker commit tf-developer-sandbox $target_name || {
  echo "ERROR: failed to commit tf-developer-sandbox"
  exit 1
}
target_tag="$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox:$CONTRAIL_CONTAINER_TAG"
sudo docker tag $target_name $target_tag || {
  echo "ERROR: failed to tag container $target_tag"
  exit 1
}
sudo docker push $target_tag || {
  echo "ERROR: failed to push container $target_tag"
  exit 1
}

EOF

echo "INFO: Fetch finished"
