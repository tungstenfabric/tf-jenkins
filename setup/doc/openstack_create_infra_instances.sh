#tf-jenkins
openstack volume create --size 300 --image ubuntu-focal --bootable tf-jenkins
openstack server create --flavor v1-standard-16 --key-name plab --network management --volume tf-jenkins --security-group allow_all tf-jenkins
openstack floating ip create --floating-ip-address 10.87.85.46 public1
openstack server add floating ip tf-jenkins 10.87.85.46

#tf-jenkins-slave
openstack volume create --size 200 --image ubuntu-focal --bootable tf-jenkins-slave
openstack server create --flavor v3-standard-8 --key-name plab --network management --volume tf-jenkins-slave --security-group allow_all tf-jenkins-slave
openstack floating ip create --floating-ip-address 10.87.85.54 public1
openstack server add floating ip tf-jenkins-slave 10.87.85.54

#tf-nexus
openstack volume create --size 2000 --image ubuntu-focal --bootable tf-nexus-root
openstack volume create --size 2000  tf-nexus-data
openstack server create --flavor v2-standard-4 --key-name plab --network management --volume tf-nexus-root  --security-group allow_all tf-nexus
openstack server add volume tf-nexus tf-nexus-data
openstack floating ip create --floating-ip-address 10.87.85.70 public1
openstack server add floating ip tf-nexus 10.87.85.70

#tf-mirrors
openstack volume create --size 200 --image ubuntu-focal --bootable tf-mirrors-root
openstack volume create --size 2500  tf-mirrors-data
openstack server create --flavor v2-standard-4 --key-name plab --network management --volume tf-mirrors-root --security-group allow_all tf-mirrors
openstack server add volume tf-mirrors tf-mirrors-data
openstack floating ip create --floating-ip-address 10.87.85.47 public1
openstack server add floating ip tf-mirrors 10.87.85.47

#Setup second volume on tf-mirrors and tf-nexus
#tf-mirrors
sudo su -
parted /dev/vdb
(parted) mklabel gpt
(parted) mkpart /dev/vdb1 ext4
mkfs.ext4 -L mirrorsdata /dev/vdb1
edit /etc/fstab (LABEL=mirrorsdata /var/local/mirror)

#tf-nexus
sudo su -
parted /dev/vdb
(parted) mklabel gpt
(parted) mkpart /dev/vdb1 ext4
mkfs.ext4 -L docker /dev/vdb1
edit /etc/fstab (LABEL=docker /var/lib/docker)


