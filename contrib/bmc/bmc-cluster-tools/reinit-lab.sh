#!/bin/bash

set -o pipefail

if [[ -z $1 ]]; then
    echo "$0 LAB"
    exit 1;
fi

LAB=$1

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

echo "INFO: Reinit lab $0 started"

source $my_dir/$1.env
source functions.sh

IMAGE_SSH_USER=${IMAGE_SSH_USER:-'stack'}
virsh destroy ${undercloud_vm} || true
virsh undefine --remove-all-storage ${undercloud_vm} || true

virt-clone --original ${undercloud_vm}-original --name ${undercloud_vm} --auto-clone
virsh start $undercloud_vm

$my_dir/destroy-overcloud-VMs.sh $1

wait_machine ${undercloud_vm}

#copy files to instance
scp $my_dir/$LAB-instackenv.json ${IMAGE_SSH_USER}@${undercloud_vm}:./instackenv.json
scp /root/.ssh/id_rsa stack@${undercloud_ip}:.ssh/id_rsa
ssh stack@${undercloud_ip} 'ssh-keygen -y -f .ssh/id_rsa >.ssh/id_rsa.pub'


#if [[ -n $operator_vm ]]; then
#    virt-clone --original ${operator_vm}-original --name ${operator_vm} --auto-clone
#    virsh start ${operator_vm}
#fi



if [[ -n $ipa_vm ]]; then
    virsh destroy ${ipa_vm} || true
    virsh undefine --remove-all-storage ${ipa_vm} || true

    virt-clone --original ${ipa_vm}-original --name ${ipa_vm} --auto-clone
    virsh start $ipa_vm

    wait_machine  $ipa_vm
fi

echo "INFO: $0 finished successfully"

