#!/bin/bash
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ -n "$JUMPHOST" ]]; then
    source "$my_dir/../../infra/${JUMPHOST}/definitions"
else
    source "$my_dir/definitions"
fi

if ! ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip "tar -czf logs.tgz -C \$HOME/output logs" ; then
  echo "INFO: logs folder is absent on target"
  exit
fi

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $IMAGE_SSH_USER@$instance_ip:logs.tgz $WORKSPACE/
rm -rf $WORKSPACE/logs
tar -zxf $WORKSPACE/logs.tgz
ssh -i ${LOGS_HOST_SSH_KEY} ${SSH_OPTIONS} ${LOGS_HOST_USERNAME}@${LOGS_HOST} "mkdir -p ${FULL_LOGS_PATH}"
rsync -a -e "ssh -i ${LOGS_HOST_SSH_KEY} ${SSH_OPTIONS}" ${WORKSPACE}/logs/ ${LOGS_HOST_USERNAME}@${LOGS_HOST}:${FULL_LOGS_PATH} || /bin/true
rm -rf $WORKSPACE/logs $WORKSPACE/logs.tgz

echo "INFO: Logs collected at ${FULL_LOGS_PATH}"
