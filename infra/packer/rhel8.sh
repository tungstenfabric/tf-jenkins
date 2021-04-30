#!/bin/bash -eE
set -o pipefail

cat << EOF > local.repo

[BaseOS]
Name=Red Hat Enterprise Linux 8.0 BaseOS
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$CI_DOMAIN/repos/rhel8/latest/rhel-8-for-x86_64-baseos-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[AppStream]
Name=Red Hat Enterprise Linux 8.0 AppStream
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$CI_DOMAIN/repos/rhel8/latest/rhel-8-for-x86_64-appstream-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[rhosp16.1]
Name=Openstack 16 for Red Hat Enterprise Linux 8.2
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$CI_DOMAIN/repos/rhel8/latest/openstack-16.1-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[Satellite]
Name=Satellite tools 6.5 for Red Hat Enterprise Linux 8.0
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$CI_DOMAIN/repos/rhel8/latest/satellite-tools-6.5-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[Ansible2.x]
Name=Ansible 2.x for Red Hat Enterprise Linux 8.x
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$CI_DOMAIN/repos/rhel8/latest/ansible-2-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[HighAvailability]
Name=Red Hat Enterprise Linux 8.0 for High Availability
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$CI_DOMAIN/repos/rhel8/latest/rhel-8-for-x86_64-highavailability-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[FastDatapath]
Name=Fast Datapath for Red Hat Enterprise Linux 8.0
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$CI_DOMAIN/repos/rhel8/latest/fast-datapath-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[Ceph]
Name=Ceph for Red Hat Enterprise Linux 8.0
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$CI_DOMAIN/repos/rhel8/latest/rhceph-4-tools-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

EOF

sudo rm -rf /etc/yum.repos.d/redhat.repo
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

sudo sed -i '/192\.168\.122\.1/d' /etc/resolv.conf
echo "INFO: /etc/resolv.conf"
sudo cat /etc/resolv.conf
