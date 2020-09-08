#!/bin/bash -eE
set -o pipefail

cat << EOF > local.repo

# epel mirror disabled by default it is enabled explicitly only in tf-dev-env
[epel]
name=added from: http://nexus.jenkins.progmaticlab.com/repository/epel
baseurl=http://nexus.jenkins.progmaticlab.com/repository/epel
enabled=0
gpgcheck=0

[local-rhel-7-server-rpms]
name = Red Hat Enterprise Linux 7 Server (RPMs) local
baseurl = http://rhel7-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-optional-rpms]
name = Red Hat Enterprise Linux 7 Server - Optional (RPMs) local
baseurl = http://rhel7-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-optional-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-extras-rpms]
name = Red Hat Enterprise Linux 7 Server - Extras (RPMs) local
baseurl = http://rhel7-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-extras-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-openstack-13-rpms]
name = Red Hat OpenStack Platform 13 for RHEL 7 (RPMs) local
baseurl = http://rhel7-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-openstack-13-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-openstack-13-devtools-rpms]
name = Red Hat OpenStack Platform Dev Tools 13 for RHEL 7 (RPMs) local
baseurl = http://rhel7-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-openstack-13-devtools-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-ose-3.11-rpms]
name = Red Hat OSE 3.11 for RHEL 7 (RPMs) local
baseurl = http://rhel7-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-ose-3.11-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-ansible-2.6-rpms]
name = Red Hat Ansible 2.6 for RHEL 7 (RPMs) local
baseurl = http://rhel7-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-ansible-2.6-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-fast-datapath-rpms]
name = Red Hat Fast Datapath for RHEL 7 (RPMs) local
baseurl = http://rhel7-mirrors.tf-jenkins.progmaticlab.com/rhel-7-fast-datapath-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-server-rhscl-7-rpms]
name = Red Hat Software collections 7 (RPMs) local
baseurl = http://rhel7-mirrors.tf-jenkins.progmaticlab.com/rhel-server-rhscl-7-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-ha-for-rhel-7-server-rpms]
name = Red Hat HA for RHEL 7 (RPMs) local
baseurl = http://rhel7-mirrors.tf-jenkins.progmaticlab.com/rhel-ha-for-rhel-7-server-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

EOF

sudo sed 's/enabled=1/enabled=0/g' /etc/yum/pluginconf.d/subscription-manager.conf > subscription-manager.conf.temp
sudo cp -f subscription-manager.conf.temp /etc/yum/pluginconf.d/subscription-manager.conf
rm -rf subscription-manager.conf.temp
sudo mv local.repo /etc/yum.repos.d/

sudo yum update -y
sudo sed -i '/192\.168\.122\.1/d' /etc/resolv.conf
