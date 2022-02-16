#!/bin/bash -e

set -o pipefail

if [[ -z $1 ]]; then
    echo "$0 LAB [backup_prefix]"
    exit 1;
fi

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/$1.env

source $my_dir/functions.sh

backup_postfix=${2:-'backup'}

echo "Backup all VMs with postfix $backup_postfix"

virsh destroy ${undercloud_vm} || true
virt-clone --original ${undercloud_vm} --name "${undercloud_vm}_${backup_postfix}" --auto-clone

if [[ -n $ipa_vm ]]; then
    virsh destroy ${ipa_vm} || true
    virt-clone --original ${ipa_vm} --name "${ipa_vm}_${backup_postfix}" --auto-clone
fi

if [[ -n $operator_vm ]]; then
    virsh destroy ${operator_vm} || true
    virt-clone --original ${operator_vm} --name "${operator_vm}_${backup_postfix}" --auto-clone
fi

for vm in "${!node_4_vm[@]}"; do
  ip_addr=${node_4_vm[$vm]};
  vbmc_port=${vbmc_port_4_vm[$vm]}
  ssh $ip_addr virsh destroy $vm || true
  ssh $ip_addr virt-clone --original ${vm} --name "${vm}_${backup_postfix}" --auto-clone
done


echo "Success"


