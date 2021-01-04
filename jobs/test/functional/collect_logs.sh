#!/bin/bash

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"

rm -rf $WORKSPACE/logs
mkdir -p $WORKSPACE/logs
pushd $WORKSPACE/logs
if ! rsync -a -e "$ssh_cmd" $IMAGE_SSH_USER@$instance_ip:logs.tgz . ; then
  echo "WARNING: logs.tgz is absent on worker"
  exit
fi

tar -xvf logs.tgz
rm logs.tgz
popd

FULL_LOGS_PATH="${LOGS_PATH}/${JOB_LOGS_PATH}/test-${TARGET}"
ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS $LOGS_HOST_USERNAME@$LOGS_HOST "mkdir -p $FULL_LOGS_PATH"
rsync -a -e "ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS" $WORKSPACE/logs/ $LOGS_HOST_USERNAME@$LOGS_HOST:$FULL_LOGS_PATH
rm -rf $WORKSPACE/logs

echo "INFO: logs saved"
