#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE=${ENV_FILE:-"$WORKSPACE/stackrc.$JOB_NAME.env"}
source $ENV_FILE

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin
cd src/tungstenfabric/tf-devstack/helm
ORCHESTRATOR=$ORCHESTRATOR ./run.sh logs
EOF

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $IMAGE_SSH_USER@$instance_ip:logs.tgz $WORKSPACE/logs.tgz

pushd $WORKSPACE
tar -xzf logs.tgz
if [[ -z $CONF_PLATFORM ]]; then # The script starts from job directly
    LOGS_FILE_PATH="job_$JOB_NAME\_$BUILD_NUMBER"
else # The script starts from pipeline
    LOGS_FILE_PATH="pipeline_$CONF_PLATFORM\_$BUILD_NUMBER"
fi
ssh -i $ARCHIVE_SSH_KEY $SSH_OPTIONS $ARCHIVE_USERNAME@$ARCHIVE_HOST "mkdir -p /var/www/logs/jenkins_logs/$LOGS_FILE_PATH"
rsync -a -e "ssh -i $ARCHIVE_SSH_KEY $SSH_OPTIONS" $WORKSPACE/logs $ARCHIVE_USERNAME@$ARCHIVE_HOST:/var/www/logs/jenkins_logs/$LOGS_FILE_PATH
rm -rf $WORKSPACE/logs
popd
