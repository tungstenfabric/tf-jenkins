#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$WORKSPACE/global.env"
source "$WORKSPACE/stackrc.$JOB_NAME.env" || /bin/true
source "${WORKSPACE}/deps.${JOB_NAME}.${JOB_RND}.env" || /bin/true
source "${WORKSPACE}/vars.${JOB_NAME}.${JOB_RND}.env" || /bin/true

cat $my_dir/../../mirrors/mirror-pip.conf | envsubst > "$WORKSPACE/mirror-pip.conf"
rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$WORKSPACE/mirror-pip.conf" ${IMAGE_SSH_USER}@${instance_ip}:./pip.conf
cat $my_dir/../../mirrors/mirror-docker-daemon.json | envsubst > "$WORKSPACE/mirror-docker-daemon.json"
rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$WORKSPACE/mirror-docker-daemon.json" ${IMAGE_SSH_USER}@${instance_ip}:./docker-daemon.json
cat $my_dir/../../mirrors/ubuntu18-sources.list | envsubst > "$WORKSPACE/ubuntu18-sources.list"
rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$WORKSPACE/ubuntu18-sources.list" ${IMAGE_SSH_USER}@${instance_ip}:./ubuntu18-sources.list

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
sudo cp -f ./pip.conf /etc/pip.conf
sudo mkdir -p /etc/docker/
sudo cp -f ./docker-daemon.json /etc/docker/daemon.json

echo "INFO: Update ubuntu OS"
sudo sudo cp -f ./ubuntu18-sources.list /etc/apt/sources.list
echo "APT::Acquire::Retries \"10\";" | sudo tee /etc/apt/apt.conf.d/80-retries
sudo cp -f /usr/share/unattended-upgrades/20auto-upgrades-disabled /etc/apt/apt.conf.d/ || /bin/true
EOF

if [ -f $my_dir/../../mirrors/ubuntu18-environment ]; then
  echo "INFO: copy additional environment to host"
  cat $my_dir/../../mirrors/ubuntu18-environment | envsubst > "$WORKSPACE/ubuntu18-environment"
  rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$WORKSPACE/ubuntu18-environment" ${IMAGE_SSH_USER}@${instance_ip}:./ubuntu18-environment
  ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip "cat ubuntu18-environment | sudo tee -a /etc/environment"
fi
