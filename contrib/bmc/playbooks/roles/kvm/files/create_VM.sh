#!/bin/bash

#This script must be run on KVM host for overcloud VMs

if [[ -z $1 ]] || [[ -z $2 ]]; then
   echo "./$0 VM_NAME OS_VARIANT [IMAGE_POOL] [VCPU] [VRAM] [DISKSPACE]"
   exit 1
fi



vm=$1
os_var=$2
image_pool=${3:-'images'}
vcpu=${4:-'8'}
vram=${5:-'32768'}
diskspace=${6:-'50G'}

kvm_host=$(hostname -a)

echo "INFO: $kvm_host creating VM: $vm $os_var pool=$image_pool vcpu=$vcpu vram=$vram diskspace=$diskspace"

qemu-img create -f qcow2 /var/lib/libvirt/images/$vm.qcow2 $diskspace

virt-install --name $vm \
  --disk /var/lib/libvirt/${image_pool}/${vm}.qcow2 \
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

