#!/bin/bash

if [[ -z $1 ]] || [[ -z $2 ]]; then
   echo "./$0 VM_NAME OS_VARIANT"
   exit 1
fi
      

vcpus=8
vram=32000

vm=$1
os_var=$2
echo $vm $os_var

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

