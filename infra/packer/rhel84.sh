#!/bin/bash -eE
set -o pipefail

cat << EOF > local.repo

[BaseOS]
Name=Red Hat Enterprise Linux 8.4 BaseOS
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$SLAVE_REGION.$CI_DOMAIN/repos/rhel84/$REPOS_CHANNEL/rhel-8-for-x86_64-baseos-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[CodeReadyBuilder]
Name=Red Hat Enterprise Linux 8.4 CodeReadyBuilder
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$SLAVE_REGION.$CI_DOMAIN/repos/rhel84/$REPOS_CHANNEL/codeready-builder-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[AppStream]
Name=Red Hat Enterprise Linux 8.4 AppStream
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$SLAVE_REGION.$CI_DOMAIN/repos/rhel84/$REPOS_CHANNEL/rhel-8-for-x86_64-appstream-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[AppStreamDebug]
Name=Red Hat Enterprise Linux 8.4 AppStreamDebug
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$SLAVE_REGION.$CI_DOMAIN/repos/rhel84/$REPOS_CHANNEL/rhel-8-for-x86_64-appstream-debug-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[rhosp16.2]
Name=Openstack 16.2 for Red Hat Enterprise Linux 8.4
enabled=1
baseurl=http://tf-mirrors.$SLAVE_REGION.$CI_DOMAIN/repos/rhel84/$REPOS_CHANNEL/openstack-16.2-for-rhel-8-x86_64-rpms/
cost = 600
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[Satellite]
Name=Satellite tools 6.5 for Red Hat Enterprise Linux 8.4
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$SLAVE_REGION.$CI_DOMAIN/repos/rhel84/$REPOS_CHANNEL/satellite-tools-6.5-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[Ansible2.x]
Name=Ansible 2.x for Red Hat Enterprise Linux 8.x
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$SLAVE_REGION.$CI_DOMAIN/repos/rhel84/$REPOS_CHANNEL/ansible-2-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[HighAvailability]
Name=Red Hat Enterprise Linux 8.0 for High Availability
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$SLAVE_REGION.$CI_DOMAIN/repos/rhel84/$REPOS_CHANNEL/rhel-8-for-x86_64-highavailability-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[FastDatapath]
Name=Fast Datapath for Red Hat Enterprise Linux 8.4
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$SLAVE_REGION.$CI_DOMAIN/repos/rhel84/$REPOS_CHANNEL/fast-datapath-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[AdvancedVirtualization]
Name=Advanced Virtualization for RHEL 8 x86_64
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$SLAVE_REGION.$CI_DOMAIN/repos/rhel84/$REPOS_CHANNEL/advanced-virt-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[CephTools]
Name=Ceph Tools for Red Hat Enterprise Linux 8.4
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$SLAVE_REGION.$CI_DOMAIN/repos/rhel84/$REPOS_CHANNEL/rhceph-4-tools-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

[CephMon]
Name=Ceph Mon for Red Hat Enterprise Linux 8.4
enabled=1
gpgcheck=1
baseurl=http://tf-mirrors.$SLAVE_REGION.$CI_DOMAIN/repos/rhel84/$REPOS_CHANNEL/rhceph-4-mon-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
cost = 600

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
