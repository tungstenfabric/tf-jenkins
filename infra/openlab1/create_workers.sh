#!/bin/bash -eE
set -o pipefail

# Currently only one worker can be created.

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/definitions"

cat <<EOF | ssh -i $OPENLAB1_SSH_KEY $SSH_OPTIONS -p 30001 jenkins@openlab.tf-jenkins.progmaticlab.com
[ "${DEBUG,,}" == "true" ] && set -x
export LIBVIRT_DEFAULT_URI=qemu:///system
export PATH=\$PATH:/usr/sbin
virsh destroy $VM_NAME || /bin/true
virsh undefine $VM_NAME  || /bin/true
rm -f $VM_NAME.qcow2
virt-clone --original $ENVIRONMENT_OS --name $VM_NAME --auto-clone --file $VM_NAME.qcow2
virsh start $VM_NAME
echo "VM is spinned"
EOF

stackrc_file=${stackrc_file:-"stackrc.$JOB_NAME.env"}
stackrc_file_path=$WORKSPACE/$stackrc_file
echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" > "$stackrc_file"
echo "export instance_ip=$INSTANCE_IP" >> "$stackrc_file"
echo "export SSH_EXTRA_OPTIONS=\"-o ProxyCommand=\\\"ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -W %h:%p -i \$OPENLAB1_SSH_KEY -l jenkins -p 30001 openlab.tf-jenkins.progmaticlab.com\\\"\"" >> "$stackrc_file"
echo "export mgmt_ip=$INSTANCE_IP" >> "$stackrc_file"
source "$stackrc_file"

timeout 300 bash -c "\
while /bin/true ; do \
  ssh -i $OPENLAB1_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS $IMAGE_SSH_USER@$instance_ip 'uname -a' && break ; \
  sleep 10 ; \
done"

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$INSTACKENV} $IMAGE_SSH_USER@$instance_ip:./
