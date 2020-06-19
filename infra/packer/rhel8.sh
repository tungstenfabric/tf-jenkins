#!/bin/bash -eE
set -o pipefail

cat << EOF > local.repo

[BaseOS]
Name=Red Hat Enterprise Linux 8.0 BaseOS
enabled=1
gpgcheck=1
baseurl=http://rhel8-mirrors.tf-jenkins.progmaticlab.com/base/rhel-8-for-x86_64-baseos-rpms/

[AppStream]
Name=Red Hat Enterprise Linux 8.0 AppStream
enabled=1
gpgcheck=1
baseurl=http://rhel8-mirrors.tf-jenkins.progmaticlab.com/appstream/rhel-8-for-x86_64-appstream-rpms/

EOF

sudo mv local.repo /etc/yum.repos.d/

sudo yum update -y
sudo sed -i '/192\.168\.122\.1/d' /etc/resolv.conf
