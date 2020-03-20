#!/bin/bash -eE
set -o pipefail

yum-config-manager --disable \*
yum-config-manager --add-repo http://pnexus.sytes.net/repository/centos7-centosplus
sed -i '$ i gpgcheck=0' /etc/yum.repos.d/pnexus.sytes.net_repository_centos7-centosplus.repo
yum-config-manager --add-repo http://pnexus.sytes.net/repository/centos7-extras
sed -i '$ i gpgcheck=0' /etc/yum.repos.d/pnexus.sytes.net_repository_centos7-extras.repo
yum-config-manager --add-repo http://pnexus.sytes.net/repository/centos7-os
sed -i '$ i gpgcheck=0' /etc/yum.repos.d/pnexus.sytes.net_repository_centos7-os.repo
yum-config-manager --add-repo http://pnexus.sytes.net/repository/centos7-updates
sed -i '$ i gpgcheck=0' /etc/yum.repos.d/pnexus.sytes.net_repository_centos7-updates.repo
yum-config-manager --add-repo http://pnexus.sytes.net/repository/epel
sed -i '$ i gpgcheck=0' /etc/yum.repos.d/pnexus.sytes.net_repository_epel.repo
sudo yum update -y
