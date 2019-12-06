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



rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $IMAGE_SSH_USER@$instance_ip:logs.tgz $WORKSPACE/logs.tgz

tar xzf $WORKSPACE/logs.tgz

#TODO Remove after global.env will be fixed
ARCHIVE_HOST=pnexus.sytes.net
ls -lr $WORKSPACE/logs

ssh -i $ARCHIVE_SSH_KEY $SSH_OPTIONS $ARCHIVE_USERNAME@$ARCHIVE_HOST "mkdir -p /var/www/logs/jenkins_logs/$instance_id"

rsync -a -e "ssh -i $ARCHIVE_SSH_KEY $SSH_OPTIONS" $WORKSPACE/logs $ARCHIVE_USERNAME@$ARCHIVE_HOST:/var/www/logs/jenkins_logs/$instance_id