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

rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$my_dir/../../mirrors/mirror-pip.conf" ${IMAGE_SSH_USER}@${instance_ip}:./pip.conf
rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$my_dir/../../mirrors/mirror-docker-daemon.json" ${IMAGE_SSH_USER}@${instance_ip}:./docker-daemon.json
rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$my_dir/resolv.conf" ${IMAGE_SSH_USER}@${instance_ip}:./resolv.conf

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
sudo cp -f ./pip.conf /etc/pip.conf
sudo cp -f ./resolv.conf /etc/resolv.conf
sudo mkdir -p /etc/docker/
sudo cp -f ./docker-daemon.json /etc/docker/daemon.json
#sudo kill -SIGHUP $(pidof dockerd)
EOF

if [ -f $my_dir/../../mirrors/centos7-environment ]; then
  echo "INFO: copy additional environment to host"
  rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$my_dir/../../mirrors/centos7-environment" ${IMAGE_SSH_USER}@${instance_ip}:./centos7-environment
  ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip "cat centos7-environment | sudo tee -a /etc/environment"
fi

# Switch REPOS_CHANNEL
if [[ -n "$REPOS_CHANNEL" && "$REPOS_CHANNEL" != 'latest' ]]; then
  sed -i "s|/latest/|/${REPOS_CHANNEL}/|g" $my_dir/../../mirrors/mirror-base.repo
fi

if [ -f $my_dir/../../mirrors/mirror-base.repo ]; then
  echo "INFO: copy mirror-base.repo to host"
  rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$my_dir/../../mirrors/mirror-base.repo" ${IMAGE_SSH_USER}@${instance_ip}:./mirror-base.repo
  ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip "sudo rm -f /etc/yum.repos.d/*; sudo cp mirror-base.repo /etc/yum.repos.d/"
fi
