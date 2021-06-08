#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

if [ -z ${REPOS_TYPE} ]; then
  echo "ERROR: REPOS_TYPE is undefined or empty"
  exit 1
fi

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

cat <<EOF | ssh -i $REPOUPDATER_SSH_KEY $SSH_OPTIONS $REPOUPDATER_USER_NAME@tf-mirrors.$SLAVE_REGION.$CI_DOMAIN
export SLAVE_REGION=$SLAVE_REGION
export CI_DOMAIN=$CI_DOMAIN
./src/tungstenfabric/tf-jenkins/jobs/update-stage-images/publish_stage.sh ${REPOS_TYPE}
EOF
