#!/bin/bash -e

set -o pipefail

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ -z $1 ]]; then
    echo "$0 <LAB> [backup_prefix]"
    exit 1;
fi

source $my_dir/$1.env
source $my_dir/functions.sh

backup_postfix=${2:-'backup'}
echo "INFO: Backup prefix: $backup_postfix"

virt-clone --original "${undercloud_vm}_$backup_postfix" --name ${undercloud_vm} --auto-clone
virsh start $undercloud_vm

for vm in "${!node_4_vm[@]}"; do
  ip_addr=${node_4_vm[$vm]};
  vbmc_port=${vbmc_port_4_vm[$vm]}
  ssh $ip_addr virt-clone --original "${vm}_$backup_postfix" --name $vm --auto-clone
  #add_vbmc $ip_addr $vm $vbmc_port
  ssh $ip_addr virsh start $vm
done


#$my_dir/generate_instackenv.sh

#Sometimes it's unavailable without reboot.
#virsh destroy ${undercloud_vm}
#virsh start ${undercloud_vm}

if [[ -n $operator_vm ]]; then
    virt-clone --original "${operator_vm}_${backup_postfix}" --name ${operator_vm} --auto-clone
    virsh start $operator_vm
fi

if [[ -n $ipa_vm ]]; then
    virt-clone --original "${ipa_vm}_${backup_postfix}" --name ${ipa_vm} --auto-clone
    virsh start $ipa_vm

    sleep 60
    scp /root/.ssh/id_rsa stack@${undercloud_ip}:.ssh/id_rsa
    ssh stack@${undercloud_ip} 'ssh-keygen -y -f .ssh/id_rsa >.ssh/id_rsa.pub'
fi


