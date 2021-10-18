#!/bin/bash -e

if [[ -z $1 ]]; then
    echo "$0 LAB"
    exit 1;
fi

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/$1.env

source $my_dir/functions.sh

echo "Backup all VMs with postfix '_backup'

virsh destroy $undercloud_vm || true
virt-clone --original $undercloud_vm --name ${undercloud_vm}_backup --auto-clone

for vm in "${!node_4_vm[@]}"; do
  ip_addr=${node_4_vm[$vm]};
  vbmc_port=${vbmc_port_4_vm[$vm]}
  ssh $ip_addr virsh destroy $vm || true
  ssh $ip_addr virt-clone --original ${vm} --name "${vm}_backup" --auto-clone
done

echo "Success"

