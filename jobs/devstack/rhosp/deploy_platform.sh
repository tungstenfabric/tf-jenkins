#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


source "$my_dir/definitions"
stackrc_file="stackrc.$JOB_NAME.env"
source $WORKSPACE/$stackrc_file

echo "INFO: Deploy platform for $JOB_NAME"
rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/$stackrc_file $IMAGE_SSH_USER@$mgmt_ip:./
rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$mgmt_ip:./

#Copy ssh key to undercloud
rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKER_SSH_KEY $IMAGE_SSH_USER@$mgmt_ip:.ssh/id_rsa
ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$mgmt_ip 'ssh-keygen -y -f .ssh/id_rsa >.ssh/id_rsa.pub'
ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$mgmt_ip chmod 600 .ssh/id_rsa*

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$mgmt_ip || res=1
export RHEL_USER=$RHEL_USER
export RHEL_PASSWORD=$RHEL_PASSWORD
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export ENABLE_RHEL_REGISTRATION='false'
export PATH=\$PATH:/usr/sbin
source $stackrc_file
cd src/tungstenfabric/tf-devstack/rhosp
./run.sh platform
EOF

echo "INFO: Deploy platform finished"
exit $res
