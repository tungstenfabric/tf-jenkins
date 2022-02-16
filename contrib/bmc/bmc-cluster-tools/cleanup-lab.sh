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

virsh destroy $undercloud_vm
virsh undefine --remove-all-storage $undercloud_vm

if [[ -n $ipa_vm ]]; then
    virsh destroy $ipa_vm
    virsh undefine --remove-all-storage $ipa_vm
fi

if [[ -n $operator_vm ]]; then
    virsh destroy ${operator_vm}
    virsh undefine --remove-all-storage $operator_vm
fi


for vm in "${!node_4_vm[@]}"; do
  ip_addr=${node_4_vm[$vm]};
  #del_vbmc $ip_addr $vm
  ssh $ip_addr virsh destroy $vm
  ssh $ip_addr virsh undefine --remove-all-storage $vm
done


