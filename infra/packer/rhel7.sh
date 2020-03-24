#!/bin/bash -eE
set -o pipefail

cat << EOF > local.repo
[local-rhel-7-server-rpms]
name = Red Hat Enterprise Linux 7 Server (RPMs) local
baseurl = http://rhel-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-optional-rpms]
name = Red Hat Enterprise Linux 7 Server - Optional (RPMs) local
baseurl = http://rhel-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-optional-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-extras-rpms]
name = Red Hat Enterprise Linux 7 Server - Extras (RPMs) local
baseurl = http://rhel-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-extras-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-openstack-13-rpms]
name = Red Hat OpenStack Platform 13 for RHEL 7 (RPMs) local
baseurl = http://rhel-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-openstack-13-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-ose-3.11-rpms]
name = Red Hat OSE 3.11 for RHEL 7 (RPMs) local
baseurl = http://rhel-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-ose-3.11-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-ansible-2.6-rpms]
name = Red Hat Ansible 2.6 for RHEL 7 (RPMs) local
baseurl = http://rhel-mirrors.tf-jenkins.progmaticlab.com/rhel-7-server-ansible-2.6-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-fast-datapath-rpms]
name = Red Hat Fast Datapath for RHEL 7 (RPMs) local
baseurl = http://rhel-mirrors.tf-jenkins.progmaticlab.com/rhel-7-fast-datapath-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

EOF

sudo mv local.repo /etc/yum.repos.d/

sudo yum update -y
sudo sed -i '/192\.168\.122\.1/d' /etc/resolv.conf
