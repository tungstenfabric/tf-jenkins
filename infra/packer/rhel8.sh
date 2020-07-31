#!/bin/bash -eE
set -o pipefail

cat << EOF > local.repo

[BaseOS]
Name=Red Hat Enterprise Linux 8.0 BaseOS
enabled=1
gpgcheck=1
baseurl=http://rhel8-mirrors.tf-jenkins.progmaticlab.com/base/rhel-8-for-x86_64-baseos-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[AppStream]
Name=Red Hat Enterprise Linux 8.0 AppStream
enabled=1
gpgcheck=1
baseurl=http://rhel8-mirrors.tf-jenkins.progmaticlab.com/appstream/rhel-8-for-x86_64-appstream-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhosp16.0]
Name=Openstack 16 for Red Hat Enterprise Linux 8.0
enabled=1
gpgcheck=1
baseurl=http://rhel8-mirrors.tf-jenkins.progmaticlab.com/openstack/openstack-16-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhosp16.1]
Name=Openstack 16 for Red Hat Enterprise Linux 8.2
enabled=1
gpgcheck=1
baseurl=http://rhel8-mirrors.tf-jenkins.progmaticlab.com/openstack/openstack-16.1-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[Satellite]
Name=Satellite tools 6.5 for Red Hat Enterprise Linux 8.0
enabled=1
gpgcheck=1
baseurl=http://rhel8-mirrors.tf-jenkins.progmaticlab.com/satellite/satellite-tools-6.5-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[Ansible2.8]
Name=Ansible 2.8 for Red Hat Enterprise Linux 8.0
enabled=1
gpgcheck=1
baseurl=http://rhel8-mirrors.tf-jenkins.progmaticlab.com/ansible/ansible-2.8-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[Ansible2.x]
Name=Ansible 2.x for Red Hat Enterprise Linux 8.x
enabled=1
gpgcheck=1
baseurl=http://rhel8-mirrors.tf-jenkins.progmaticlab.com/ansible/ansible-2-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[HighAvailability]
Name=Red Hat Enterprise Linux 8.0 for High Availability
enabled=1
gpgcheck=1
baseurl=http://rhel8-mirrors.tf-jenkins.progmaticlab.com/ha/rhel-8-for-x86_64-highavailability-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[FastDatapath]
Name=Fast Datapath for Red Hat Enterprise Linux 8.0
enabled=1
gpgcheck=1
baseurl=http://rhel8-mirrors.tf-jenkins.progmaticlab.com/datapath/fast-datapath-for-rhel-8-x86_64-rpms/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

EOF

sudo rm -rf /etc/yum.repos.d/redhat.repo
sudo yum clean all
sudo subscription-manager clean

#prevent subscription manager error
sudo sed 's/enabled=1/enabled=0/g' /etc/yum/pluginconf.d/subscription-manager.conf > subscription-manager.conf.temp
sudo cp -f subscription-manager.conf.temp /etc/yum/pluginconf.d/subscription-manager.conf
rm -rf subscription-manager.conf.temp
sudo mv local.repo /etc/yum.repos.d/

sudo yum update -y
sudo sed -i '/192\.168\.122\.1/d' /etc/resolv.conf
