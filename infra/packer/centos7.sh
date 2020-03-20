#!/bin/bash -eE
set -o pipefail

sudo yum update -y
exit

sudo -- sh <<MANY
yum-config-manager --disable \*
yum-config-manager --add-repo http://pnexus.sytes.net/repository/centos7-extras
sed -i '$ i gpgcheck=0' /etc/yum.repos.d/pnexus.sytes.net_repository_centos7-extras.repo
yum-config-manager --add-repo http://pnexus.sytes.net/repository/centos7-os
sed -i '$ i gpgcheck=0' /etc/yum.repos.d/pnexus.sytes.net_repository_centos7-os.repo
yum-config-manager --add-repo http://pnexus.sytes.net/repository/centos7-updates
sed -i '$ i gpgcheck=0' /etc/yum.repos.d/pnexus.sytes.net_repository_centos7-updates.repo
yum-config-manager --add-repo http://pnexus.sytes.net/repository/epel
sed -i '$ i gpgcheck=0' /etc/yum.repos.d/pnexus.sytes.net_repository_epel.repo
yum-config-manager --add-repo http://pnexus.sytes.net/repository/docker-ce-stable
sed -i '$ i gpgcheck=0' /etc/yum.repos.d/pnexus.sytes.net_repository_docker-ce-stable.repo
yum-config-manager --add-repo http://pnexus.sytes.net/repository/google-chrome
sed -i '$ i gpgcheck=0' /etc/yum.repos.d/pnexus.sytes.net_repository_google-chrome.repo
yum-config-manager --add-repo http://pnexus.sytes.net/repository/openstack-rocky
sed -i '$ i gpgcheck=0' /etc/yum.repos.d/pnexus.sytes.net_repository_openstack-rocky.repo

yum update -y
MANY
