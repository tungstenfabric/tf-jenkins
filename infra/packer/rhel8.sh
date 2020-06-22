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

EOF

sudo mv /etc/yum.repos.d/redhat.repo ~/
sudo yum clean all
sudo subscription-manager clean

#prevent subscription manager error
sudo sed 's/enabled=1/enabled=0/g' /etc/yum/pluginconf.d/subscription-manager.conf > subscription-manager.conf.temp
sudo cp -f subscription-manager.conf.temp /etc/yum/pluginconf.d/subscription-manager.conf
rm -rf subscription-manager.conf.temp
sudo mv local.repo /etc/yum.repos.d/

sudo yum update -y
sudo sed -i '/192\.168\.122\.1/d' /etc/resolv.conf
