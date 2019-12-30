#!/bin/bash
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin

sudo docker cp tf-developer-sandbox:/root/contrail/contrail-container-builder/containers .
sudo find ./containers/ -not -name '*.log' -delete &>/dev/null || /bin/true
sudo mv containers container-builder
tar -czf container-builder.tgz container-builder
sudo rm -rf ./container-builder

sudo docker cp tf-developer-sandbox:/root/contrail/contrail-deployers-containers/containers .
sudo find ./containers/ -not -name '*.log' -delete &>/dev/null || /bin/true
sudo mv containers deployers-containers
tar -czf deployers-containers.tgz deployers-containers
sudo rm -rf ./deployers-containers

mkdir -p contrail-test
for file in \$(sudo docker exec tf-developer-sandbox ls /root/contrail/third_party/contrail-test/ | grep log$)
do
  sudo docker cp tf-developer-sandbox:/root/contrail/third_party/contrail-test/\${file} ./contrail-test
done
tar -czf contrail-test.tgz contrail-test
sudo rm -rf ./contrail-test
EOF

rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" ${IMAGE_SSH_USER}@${instance_ip}:container-builder.tgz ${WORKSPACE}/
tar -zxvf  ${WORKSPACE}/container-builder.tgz

rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" ${IMAGE_SSH_USER}@${instance_ip}:deployers-containers.tgz ${WORKSPACE}/
tar -zxvf  ${WORKSPACE}/deployers-containers.tgz

rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" ${IMAGE_SSH_USER}@${instance_ip}:contrail-test.tgz ${WORKSPACE}/
tar -zxvf  ${WORKSPACE}/contrail-test.tgz

ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS} ${IMAGE_SSH_USER}@${instance_ip} rm -rf deployers-containers.tgz container-builder.tgz contrail-test.tgz

ssh -i ${LOGS_HOST_SSH_KEY} ${SSH_OPTIONS} ${LOGS_HOST_USERNAME}@${LOGS_HOST} "mkdir -p ${FULL_LOGS_PATH}"
rsync -a -e "ssh -i ${LOGS_HOST_SSH_KEY} ${SSH_OPTIONS}" ${WORKSPACE}/container-builder ${LOGS_HOST_USERNAME}@${LOGS_HOST}:${FULL_LOGS_PATH} || /bin/true
rsync -a -e "ssh -i ${LOGS_HOST_SSH_KEY} ${SSH_OPTIONS}" ${WORKSPACE}/deployers-containers ${LOGS_HOST_USERNAME}@${LOGS_HOST}:${FULL_LOGS_PATH} || /bin/true
rsync -a -e "ssh -i ${LOGS_HOST_SSH_KEY} ${SSH_OPTIONS}" ${WORKSPACE}/contrail-test ${LOGS_HOST_USERNAME}@${LOGS_HOST}:${FULL_LOGS_PATH} || /bin/true

rm -rf ${WORKSPACE}/contrail-test ${WORKSPACE}/deployers-containers ${WORKSPACE}/container-builder

exit $res
