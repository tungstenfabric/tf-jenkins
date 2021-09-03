#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ -z $1 ]]; then
    echo "$0 LAB"
    exit 1;
fi

source $my_dir/$1.env
source $my_dir/functions.sh


virt-clone --original undercloud_backup --name undercloud --auto-clone
virsh start undercloud

for vm in "${!node_4_vm[@]}"; do 
  ip_addr=${node_4_vm[$vm]};
  vbmc_port=${vbmc_port_4_vm[$vm]}
  ssh $ip_addr virt-clone --original "${vm}_backup" --name $vm --auto-clone
  #add_vbmc $ip_addr $vm $vbmc_port
  ssh $ip_addr virsh start $vm
done


$my_dir/generate_instackenv.sh

#Sometimes it's unavailable without reboot. 
virsh destroy undercloud
virsh start undercloud
