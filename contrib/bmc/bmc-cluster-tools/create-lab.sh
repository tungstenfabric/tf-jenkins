#!/bin/bash

set -o pipefail

if [[ -z $1 ]]; then
    echo "$0 LAB"
    exit 1;
fi

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/$1.env
source functions.sh

virt-clone --original ${undercloud_vm}-original --name ${undercloud_vm} --auto-clone
virsh start $undercloud_vm

$my_dir/create-overcloud-VMs.sh $1

if [[ -n $operator_vm ]]; then
    virt-clone --original ${operator_vm}-original --name ${operator_vm} --auto-clone
    virsh start ${operator_vm}
fi

if [[ -n $ipa_vm ]]; then
    virt-clone --original ${ipa_vm}-original --name ${ipa_vm} --auto-clone
    virsh start $ipa_vm

    sleep 60
    scp /root/.ssh/id_rsa stack@${undercloud_ip}:.ssh/id_rsa
    ssh stack@${undercloud_ip} 'ssh-keygen -y -f .ssh/id_rsa >.ssh/id_rsa.pub'
fi

