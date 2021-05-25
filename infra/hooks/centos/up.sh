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

ssh_cmd="ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}"

cat $my_dir/../../mirrors/mirror-pip.conf | envsubst > "$WORKSPACE/mirror-pip.conf"
rsync -a -e "$ssh_cmd" "$WORKSPACE/mirror-pip.conf" ${IMAGE_SSH_USER}@${instance_ip}:./pip.conf
cat $my_dir/../../mirrors/mirror-docker-daemon.json | envsubst > "$WORKSPACE/mirror-docker-daemon.json"
rsync -a -e "$ssh_cmd" "$WORKSPACE/mirror-docker-daemon.json" ${IMAGE_SSH_USER}@${instance_ip}:./docker-daemon.json

cat <<EOF | $ssh_cmd $IMAGE_SSH_USER@$instance_ip
sudo cp -f ./pip.conf /etc/pip.conf
sudo mkdir -p /etc/docker/
sudo cp -f ./docker-daemon.json /etc/docker/daemon.json
#sudo kill -SIGHUP $(pidof dockerd)
EOF

if [ -f $my_dir/../../mirrors/centos7-environment ]; then
  echo "INFO: copy additional environment to host"
  cat $my_dir/../../mirrors/centos7-environment | envsubst > "$WORKSPACE/centos7-environment"
  rsync -a -e "$ssh_cmd" "$WORKSPACE/centos7-environment" ${IMAGE_SSH_USER}@${instance_ip}:./centos7-environment
  $ssh_cmd $IMAGE_SSH_USER@$instance_ip "cat centos7-environment | sudo tee -a /etc/environment"
fi

echo "INFO: copy mirror-base.repo to host"
cat $my_dir/../../mirrors/mirror-base.repo | envsubst > "$WORKSPACE/mirror-base.repo"
rsync -a -e "$ssh_cmd" "$WORKSPACE/mirror-base.repo" ${IMAGE_SSH_USER}@${instance_ip}:./mirror-base.repo
$ssh_cmd $IMAGE_SSH_USER@$instance_ip "sudo rm -f /etc/yum.repos.d/*; sudo cp mirror-base.repo /etc/yum.repos.d/"

# TODO: detect interface name
echo "INFO: do not set default gateway for second interface"
if [[ "${USE_DATAPLANE_NETWORK,,}" == "true" ]]; then
  $ssh_cmd $IMAGE_SSH_USER@$instance_ip "printf 'DEFROUTE=no\nPEERDNS=no\n' | sudo tee -a /etc/sysconfig/network-scripts/ifcfg-eth1 ; sudo systemctl restart network.service"
fi
