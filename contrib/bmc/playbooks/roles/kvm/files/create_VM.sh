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

#Creating additional disks for journals and OSD (ceph-ansible doesn't support osd on the root device)
if [[ "$vm" =~ 'ceph' ]]; then
    #journal disk
    #qemu-img create -f qcow2 /var/lib/libvirt/images/${vm}-0.qcow2 300M
    #ceph_disks_cmd+="  --disk /var/lib/libvirt/${image_pool}/${vm}-0.qcow2 "

    #creating osd disks
    for i in $(seq 1 4); do
       qemu-img create -f qcow2 /var/lib/libvirt/images/${vm}-${i}.qcow2 6G
       ceph_disks_cmd+="--disk /var/lib/libvirt/${image_pool}/${vm}-${i}.qcow2 "
    done
fi

virt-install --name $vm \
  --disk /var/lib/libvirt/${image_pool}/${vm}.qcow2 \
  $ceph_disks_cmd \
  --vcpus=${vcpu} \
  --cpu=host \
  --ram=${vram} \
  --network bridge=br0,model=virtio \
  --network bridge=br1,model=virtio \
  --virt-type kvm \
  --import \
  --os-variant $os_var \
  --graphics vnc \
  --serial pty \
  --noautoconsole \
  --console pty,target_type=virtio

virsh destroy $vm

