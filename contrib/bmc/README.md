#Creating BMC cluster

## Generate ssh keypair and copy public key into ~/.ssh/authorized_keys on every kvm node

## Download RHEL image and copy it on every KVM node

Code example for manual setup kvm node

```
dnf install -y qemu-kvm libvirt  libguestfs-tools virt-install vim httpd tmux yum-utils openvswitch2.11.x86_64

dnf update -y

#yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
#dnf install -y packer


hugepages
grub2-editenv - set "kernelopts=root=/dev/mapper/5a8s1--node4--vg00-lv_root ro crashkernel=auto resume=UUID=442377c7-f8ca-4323-9e53-4251df3b567e rd.lvm.lv=5a8s1-node4-vg00/lv_root rhgb quiet rootdelay=10 default_hugepagesz=1G hugepagesz=1G hugepages=118"
reboot


ipaddr=$(ip address list dev eno1 | grep 10.87.72 | awk '{print $2}' | cut -d '/' -f1)
cp /etc/sysconfig/network-scripts/ifcfg-eno1 /etc/sysconfig/network-scripts/ifcfg-eno1.bak

sed -i /etc/sysconfig/network-scripts/ifcfg-eno1 -e 's/BOOTPROTO=dhcp/BOOTPROTO=none/'
echo "IPADDR=$ipaddr" >> /etc/sysconfig/network-scripts/ifcfg-eno1
echo "PREFIX=25" >> /etc/sysconfig/network-scripts/ifcfg-eno1
echo "GATEWAY=10.87.72.126" >> /etc/sysconfig/network

grub2-editenv list
kernelopts=$(grub2-editenv list | grep -Eo "kernelopts=.*$")
grub2-editenv - set "$kernelopts rootdelay=10 default_hugepagesz=1G hugepagesz=1G hugepages=118"
grub2-editenv list
```

## Create inventory.yaml and run ansible playbook deploy-kvm for creating bridges and setup kvm nodes 

## Create VM for mirrors

```
export LIBGUESTFS_BACKEND=direct
qemu-img create -f qcow2 /var/lib/libvirt/images/mirrors.qcow2 500G
virt-resize --expand /dev/sda1  rhel-server-7.9-x86_64-kvm.qcow2  /var/lib/libvirt/images/mirrors.qcow2


virt-customize  -a /var/lib/libvirt/images/mirrors.qcow2 \
  --run-command 'xfs_growfs /' \
  --root-password password:c0ntrail123 \
  --hostname mirrors \
  --run-command 'sed -i "s/dhcp/none/g"  /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'echo "IPADDR=10.87.72.66" >> /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'echo "PREFIX=25" >> /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'echo "GATEWAY=10.87.72.126" >> /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'echo "DNS1=8.8.8.8" >> /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
  --ssh-inject root:file:/root/.ssh/id_rsa.pub \
  --run-command 'systemctl enable sshd' \
  --run-command 'yum remove -y cloud-init' \
  --selinux-relabel

virt-install --name mirrors --ram 8192 --network bridge:br-mgmt --disk path=/var/lib/libvirt/images/mirrors.qcow2,format=qcow2,bus=virtio,cache=writeback --boot=hd 
```
Use playbook tf-jenkins/setup/playbooks/deploy-mirrors.yaml and role mirrors for setup mirror VM

## Create worker for syncing container images

```
export LIBGUESTFS_BACKEND=direct
qemu-img create -f qcow2 /var/lib/libvirt/images/sync_image_worker.qcow2 500G
virt-resize --expand /dev/sda1  rhel-server-7.9-x86_64-kvm.qcow2  /var/lib/libvirt/images/sync_image_worker.qcow2


virt-customize  -a /var/lib/libvirt/images/sync_image_worker.qcow2 \
  --run-command 'xfs_growfs /' \
  --root-password password:c0ntrail123 \
  --hostname mirrors \
  --run-command 'sed -i "s/dhcp/none/g"  /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'echo "IPADDR=10.87.72.66" >> /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'echo "PREFIX=25" >> /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'echo "GATEWAY=10.87.72.126" >> /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'echo "DNS1=8.8.8.8" >> /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
  --ssh-inject root:file:/root/.ssh/id_rsa.pub \
  --run-command 'systemctl enable sshd' \
  --run-command 'yum remove -y cloud-init' \
  --selinux-relabel

virt-install --name sync_image_worker --ram 8192 --network bridge:br-mgmt --disk path=/var/lib/libvirt/images/sync_image_worker.qcow2,format=qcow2,bus=virtio,cache=writeback --boot=hd 
virsh destroy sync_image_worker
```



##Code example for creating rhosp13 VMs on kvm node 10.87.72.4

```
#!/bin/bash


vcpus=8
vram=32000

ipmi_address=10.87.72.4
vbmc_port=16230
vm='rhosp13-overcloud-controller-kvm4'

qemu-img create -f qcow2 /var/lib/libvirt/images/$vm.qcow2 100G
virt-resize --expand /dev/sda1 rhel-server-7.9-x86_64-kvm.qcow2 /var/lib/libvirt/images/$vm.qcow2


virt-install --name $vm \
  --disk /var/lib/libvirt/images/$vm.qcow2 \
  --vcpus=${vcpus} \
  --ram=${vram} \
  --network bridge=br-data,model=virtio \
  --virt-type kvm \
  --import \
  --os-variant rhel7.0 \
  --graphics vnc \
  --serial pty \
  --noautoconsole \
  --console pty,target_type=virtio
 
virsh destroy $vm
mac_address=$(virsh dumpxml $vm | grep 'mac address=' | grep -Eo '[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}')
vbmc add --no-daemon --port $vbmc_port --address $ipmi_address $vm

vbmc_port=16231
vm='rhosp13-overcloud-contrailcontroller-kvm4'

qemu-img create -f qcow2 /var/lib/libvirt/images/$vm.qcow2 100G
virt-resize --expand /dev/sda1 rhel-server-7.9-x86_64-kvm.qcow2 /var/lib/libvirt/images/$vm.qcow2


virt-install --name $vm \
  --disk /var/lib/libvirt/images/$vm.qcow2 \
  --vcpus=${vcpus} \
  --ram=${vram} \
  --network bridge=br-data,model=virtio \
  --virt-type kvm \
  --import \
  --os-variant rhel7.0 \
  --graphics vnc \
  --serial pty \
  --noautoconsole \
  --console pty,target_type=virtio
 
virsh destroy $vm
mac_address=$(virsh dumpxml $vm | grep 'mac address=' | grep -Eo '[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}')
vbmc add --no-daemon --port $vbmc_port --address $ipmi_address $vm

```



