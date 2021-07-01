#!/bin/bash -eE
set -o pipefail

cat << EOF > local.repo

[BaseOS]
Name=Red Hat Enterprise Linux 8.0 BaseOS
enabled=1
baseurl=http://10.0.3.192/repos/latest/rhel-8-for-x86_64-baseos-rpms/
cost = 500
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release


[AppStream]
Name=Red Hat Enterprise Linux 8.0 AppStream
enabled=1
baseurl=http://10.0.3.192/repos/latest/rhel-8-for-x86_64-appstream-rpms/
cost = 600
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhosp16.2]
Name=Openstack 16.2 for Red Hat Enterprise Linux 8.2
enabled=1
baseurl=http://10.0.3.192/repos/OpenStack/x86_64/os/
cost = 600
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[Satellite]
Name=Satellite tools 6.5 for Red Hat Enterprise Linux 8.0
enabled=1
baseurl=http://10.0.3.192/repos/latest/satellite-tools-6.5-for-rhel-8-x86_64-rpms/
cost = 600
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[Ansible2.x]
Name=Ansible 2.x for Red Hat Enterprise Linux 8.x
enabled=1
baseurl=http://10.0.3.192/repos/latest/ansible-2-for-rhel-8-x86_64-rpms/
cost = 600
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[HighAvailability]
Name=Red Hat Enterprise Linux 8.0 for High Availability
enabled=1
baseurl=http://10.0.3.192/repos/latest/rhel-8-for-x86_64-highavailability-rpms/
cost = 600
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[FastDatapath]
Name=Fast Datapath for Red Hat Enterprise Linux 8.0
enabled=1
baseurl=http://10.0.3.192/repos/latest/fast-datapath-for-rhel-8-x86_64-rpms/
cost = 600
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[AdvancedVirtualization]
Name=Advanced Virtualization for RHEL 8 x86_64
enabled=1
baseurl=http://10.0.3.192/repos/latest/advanced-virt-for-rhel-8-x86_64-rpms/
cost = 600
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[Ceph]
Name=Ceph for Red Hat Enterprise Linux 8.0
enabled=1
baseurl=http://10.0.3.192/repos/latest/rhceph-4-tools-for-rhel-8-x86_64-rpms/
cost = 600
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

EOF

sudo mv /etc/yum.repos.d/redhat.repo ./redhat.repo || true
sudo yum clean all
sudo subscription-manager clean

#prevent subscription manager error
sudo sed 's/enabled=1/enabled=0/g' /etc/yum/pluginconf.d/subscription-manager.conf > subscription-manager.conf.temp
sudo cp -f subscription-manager.conf.temp /etc/yum/pluginconf.d/subscription-manager.conf
rm -rf subscription-manager.conf.temp

sudo mv local.repo /etc/yum.repos.d/
echo "INFO: /etc/yum.repos.d/local.repo"
sudo cat /etc/yum.repos.d/local.repo
echo "INFO: yum update"
sudo yum update -y
sudo rm /etc/yum.repos.d/local.repo
sudo mv ./redhat.repo /etc/yum.repos.d/ || true

sudo sed -i '/192\.168\.122\.1/d' /etc/resolv.conf
echo "INFO: /etc/resolv.conf"
sudo cat /etc/resolv.conf
