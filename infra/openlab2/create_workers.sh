#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
touch "$ENV_FILE"
echo "export ENVIRONMENT_OS=$ENVIRONMENT_OS" >> "$ENV_FILE"
echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$ENV_FILE"
echo "export instance_ip=$INSTANCE_IP" >> "$ENV_FILE"
echo "export SSH_EXTRA_OPTIONS=\"-o ProxyCommand=\\\"ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -W %h:%p -i \$OPENLAB2_SSH_KEY -l jenkins -p 30002 openlab.tf-jenkins.progmaticlab.com\\\"\"" >> "$ENV_FILE"

cat <<EOF | ssh -i $OPENLAB2_SSH_KEY $SSH_OPTIONS -p 30002 jenkins@openlab.tf-jenkins.progmaticlab.com
[ "${DEBUG,,}" == "true" ] && set -x
export PATH=\$PATH:/usr/sbin
virsh destroy $VM_NAME_MAAS || /bin/true
virsh undefine $VM_NAME_MAAS || /bin/true
rm -f $VM_NAME_MAAS.qcow2
virsh destroy $VM_NAME_JUJUC || /bin/true
virsh undefine $VM_NAME_JUJUC || /bin/true
rm -f $VM_NAME_JUJUC.qcow2

virt-clone --original $ENVIRONMENT_OS --name $VM_NAME_MAAS --auto-clone --file $VM_NAME_MAAS.qcow2
virt-clone --original $ENVIRONMENT_OS --name $VM_NAME_JUJUC --auto-clone --file $VM_NAME_JUJUC.qcow2
virsh start $VM_NAME_MAAS
virsh start $VM_NAME_JUJUC
echo "VM is spinned"
EOF

source "$ENV_FILE"

timeout 300 bash -c "\
while /bin/true ; do \
  ssh -i $OPENLAB2_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS $IMAGE_SSH_USER@$instance_ip 'uname -a' && break ; \
  sleep 10 ; \
done"
