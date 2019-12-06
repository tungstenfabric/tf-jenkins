#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
echo "ORCHESTRATOR=kubernetes" >> "$ENV_FILE"
source $ENV_FILE

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin
cd src/tungstenfabric/tf-devstack/k8s_manifests
ORCHESTRATOR=$ORCHESTRATOR ./run.sh logs
EOF

#TODO Remove after debugging
echo WORKER_SSH_KEY = $WORKER_SSH_KEY 
echo SSH_OPTIONS = $SSH_OPTIONS
echo IMAGE_SSH_USER = $IMAGE_SSH_USER
echo ARCHIVE_SSH_KEY = $ARCHIVE_SSH_KEY
echo ARCHIVE_USERNAME = $ARCHIVE_USERNAME
echo ARCHIVE_HOST = $ARCHIVE_HOST

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $IMAGE_SSH_USER@$instance_ip:logs.tgz $WORKSPACE/logs.tgz

tar xzf $WORKSPACE/logs.tgz

ls -lr $WORKSPACE/logs

cat <<EOF | ssh -i $ARCHIVE_SSH_KEY $SSH_OPTIONS $ARCHIVE_USERNAME@$ARCHIVE_HOST
mkdir -p /var/www/logs/jenkins_logs/$instance_id
EOF

rsync -a -e "ssh -i $ARCHIVE_SSH_KEY $SSH_OPTIONS" $WORKSPACE/logs $ARCHIVE_USERNAME@$ARCHIVE_HOST:/var/www/logs/jenkins_logs/$instance_id