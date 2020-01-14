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

echo "INFO: Publish started"
ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip ./publish.sh
echo "INFO: Publish containers done"
