#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

tag_suffix=""
if [[ "${STABLE,,}" == "true" ]] ; then
  tag_suffix="-stable"
fi
tags="$(date --utc +"%Y-%m-%d")$tag_suffix"
tags+=",latest$tag_suffix"

publish_env_file="$WORKSPACE/publish.$JOB_NAME.env"
cat <<EOF > $publish_env_file
CONTRAIL_REGISTRY=$CONTAINER_REGISTRY
CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG
PUBLISH_REGISTRY=tungstenfabric
PUBLISH_REGISTRY_USER=$DOCKERHUB_USERNAME
PUBLISH_REGISTRY_PASSWORD=$DOCKERHUB_PASSWORD
PUBLISH_TAGS=$tags
EOF

scp -i $WORKER_SSH_KEY $SSH_OPTIONS $my_dir/publish.sh $IMAGE_SSH_USER@$instance_ip:./
scp -i $WORKER_SSH_KEY $SSH_OPTIONS $publish_env_file $IMAGE_SSH_USER@$instance_ip:./publish.env
rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: Prepare worker"
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
export WORKSPACE=\$HOME
[ "${DEBUG,,}" == "true" ] && set -x
export PATH=\$PATH:/usr/sbin
export DEBUG=$DEBUG
export REGISTRY_IP=$REGISTRY_IP
export REGISTRY_PORT=$REGISTRY_PORT
./src/tungstenfabric/tf-dev-env/common/setup_docker.sh

# to get DISTRO env variable
source ./src/tungstenfabric/tf-dev-env/common/common.sh
# setup additional packages
if [ x"\$DISTRO" == x"ubuntu" ]; then
  export DEBIAN_FRONTEND=noninteractive
  sudo -E apt-get install -y jq curl
else
  sudo yum -y install epel-release
  sudo yum install -y jq curl
fi

EOF

echo "INFO: Publish started"
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
export WORKSPACE=\$HOME
source ./publish.env
sudo -E ./publish.sh
EOF
echo "INFO: Publish containers done"
