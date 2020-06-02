#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
touch "$ENV_FILE"
echo "export IMAGE_SSH_USER=stack" >> "$ENV_FILE"
echo "export instance_ip=10.10.50.10" >> "$ENV_FILE"
echo "export SSH_EXTRA_OPTIONS=\"-o ProxyCommand=\\\"ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -W %h:%p -i \$OPENLAB1_SSH_KEY -l jenkins -p 30001 openlab.tf-jenkins.progmaticlab.com\\\"\"" >> "$ENV_FILE"

cat <<EOF | ssh -i $OPENLAB1_SSH_KEY $SSH_OPTIONS -p 30001 jenkins@openlab.tf-jenkins.progmaticlab.com
[ "${DEBUG,,}" == "true" ] && set -x
export BUILD_TAG=$BUILD_TAG
export PATH=\$PATH:/usr/sbin
virsh destroy rhosp-bmc || /bin/true
virsh undefine rhosp-bmc  || /bin/true
rm -f rhosp-bmc.qcow2
virt-clone --original $ENVIRONMENT_OS --name vm-rhosp-bmc --auto-clone --file rhosp-bmc.qcow2
virsh start rhosp-bmc
echo "VM is spinned"
EOF

source "$ENV_FILE"

timeout 300 bash -c "\
while /bin/true ; do \
  ssh -i $OPENLAB1_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS $IMAGE_SSH_USER@$instance_ip 'uname -a' && break ; \
  sleep 10 ; \
done"

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./
rsync -a -e "$ssh_cmd" $INSTACKENV $IMAGE_SSH_USER@$instance_ip:./
