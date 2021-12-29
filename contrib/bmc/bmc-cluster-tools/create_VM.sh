#!/bin/bash

#This script must be run on KVM host for overcloud VMs

if [[ -z $1 ]] || [[ -z $2 ]]; then
   echo "./$0 VM_NAME OS_VARIANT"
   exit 1
fi



vm=$1
os_var=$2
vcpu=${3:-'8'}
vram=${4:-'32768'}

kvm_host=$(hostname -a)

echo "INFO: $kvm_host creating VM: $vm $os_var vcpu=$vcpu vram=$vram"

qemu-img create -f qcow2 /var/lib/libvirt/images/$vm.qcow2 100G

virt-install --name $vm \
  --disk /var/lib/libvirt/images/$vm.qcow2 \
  --vcpus=${vcpus} \
  --ram=${vram} \
  --network bridge=br-data,model=virtio \
  --virt-type kvm \
  --import \
  --os-variant $os_var \
  --graphics vnc \
  --serial pty \
  --noautoconsole \
  --console pty,target_type=virtio

virsh destroy $vm

