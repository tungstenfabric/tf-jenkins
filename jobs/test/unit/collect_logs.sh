#!/bin/bash
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin
tar -czf logs.tgz -C \$WORKSPACE/contrail/output logs || /bin/true
EOF

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $IMAGE_SSH_USER@$instance_ip:logs.tgz $WORKSPACE/
tar -zxf  $WORKSPACE/logs.tgz 
ssh -i ${LOGS_HOST_SSH_KEY} ${SSH_OPTIONS} ${LOGS_HOST_USERNAME}@${LOGS_HOST} "mkdir -p ${FULL_LOGS_PATH}"
rsync -a -e "ssh -i ${LOGS_HOST_SSH_KEY} ${SSH_OPTIONS}" ${WORKSPACE}/logs ${LOGS_HOST_USERNAME}@${LOGS_HOST}:${FULL_LOGS_PATH} || /bin/true

echo "INFO: Logs collected at ${FULL_LOGS_PATH}"
exit $res
