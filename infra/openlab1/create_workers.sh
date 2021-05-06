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
function _run_vm() {
  local origin=\$1
  local vm=\$2
  echo "Cleanup old VM \$vm"
  virsh destroy \$vm || /bin/true
  virsh undefine \$vm  || /bin/true
  rm -f \$vm.qcow2
  echo "Clone VM \$vm from original \$origin"
  virt-clone --original \$origin --name \$vm --auto-clone --file \$vm.qcow2
  virsh start \$vm
  echo "VM \$vm is spinned"
}
_run_vm $ORIGIN_VM_NAME $VM_NAME
if [[ "${SSL_ENABLE,,}" == 'true' ]] ; then
  _run_vm $ORIGIN_IPA_VM_NAME $IPA_VM_NAME
fi
echo "VMs are started"
EOF

stackrc_file=${stackrc_file:-"stackrc.$JOB_NAME.env"}
echo "export PROVIDER=$PROVIDER" >> "$stackrc_file"
echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$WORKSPACE/$stackrc_file"
echo "export instance_ip=$instance_ip" >> "$WORKSPACE/$stackrc_file"
echo "export mgmt_ip=$instance_ip" >> "$WORKSPACE/$stackrc_file"
echo "export ipa_mgmt_ip=$ipa_mgmt_ip" >> "$WORKSPACE/$stackrc_file"
echo "export SSH_EXTRA_OPTIONS=\"-o ProxyCommand=\\\"ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -W %h:%p -i \$OPENLAB1_SSH_KEY -l jenkins -p 30001 openlab.tf-jenkins.progmaticlab.com\\\"\"" >> "$WORKSPACE/$stackrc_file"
source "$WORKSPACE/$stackrc_file"

function wait_machine() {
  local addr="$1"
  timeout 300 bash -c "\
  while /bin/true ; do \
    ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS $IMAGE_SSH_USER@$addr 'uname -a' && break ; \
    sleep 10 ; \
  done"
}

wait_machine $instance_ip
ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$my_dir/instackenv.json} $IMAGE_SSH_USER@$instance_ip:./
if [[ "${SSL_ENABLE,,}" == 'true' ]] ; then
  wait_machine $ipa_mgmt_ip
fi
