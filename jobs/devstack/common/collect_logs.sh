#!/bin/bash
set -o pipefail

deployer=$1

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
res=0

echo "INFO: wait for host"
timeout 30 bash -c "\
while /bin/true ; do \
  $ssh_cmd $IMAGE_SSH_USER@$instance_ip 'uname -a' 2>/dev/null && break ; \
  sleep 10 ; \
done" || res=1

if [[ "$res" != '0' ]]; then
  echo "ERROR: VM is not accessible. trying reboot..."
  "$my_dir/../../../infra/${SLAVE}/reboot_worker.sh $instance_ip"
  sleep 30
  res=0
  timeout 60 bash -c "\
  while /bin/true ; do \
    $ssh_cmd $IMAGE_SSH_USER@$instance_ip 'uname -a' 2>/dev/null && break ; \
    sleep 10 ; \
  done" || res=1
fi

if [[ "$res" != '0' ]]; then
  echo "ERROR: VM is not accessible"
  exit 1
fi

echo "INFO: collect logs"
${my_dir}/run_stage.sh $deployer logs || res=1

echo "INFO: Copy logs from host to workspace"
rsync -a -e "$ssh_cmd" $IMAGE_SSH_USER@$instance_ip:logs.tgz $WORKSPACE/logs.tgz

pushd $WORKSPACE
tar -xzf logs.tgz
ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS $LOGS_HOST_USERNAME@$LOGS_HOST "mkdir -p $FULL_LOGS_PATH"
rsync -a -e "ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS" $WORKSPACE/logs $LOGS_HOST_USERNAME@$LOGS_HOST:$FULL_LOGS_PATH
rm -rf $WORKSPACE/logs
echo "INFO: Logs collected at ${LOGS_URL}/${JOB_LOGS_PATH}"
popd

exit $res
