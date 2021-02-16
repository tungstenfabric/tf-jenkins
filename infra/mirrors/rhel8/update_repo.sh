#!/bin/bash -e

baseurl_prefix=${BASEURL_PREFIX:-"rhel8-mirrors.tf-jenkins.progmaticlab.com"}

declare -A repos
repos["rhel-8-for-x86_64-baseos-rpms"]="Red Hat Enterprise Linux 8 for x86_64 - BaseOS (RPMs) Extended Update Support"
repos["rhel-8-for-x86_64-appstream-rpms"]="Red Hat Enterprise Linux 8 for x86_64 - AppStream (RPMs)"
repos["rhel-8-for-x86_64-highavailability-rpms"]="Red Hat Enterprise Linux 8 for x86_64 - High Availability (RPMs) Extended Update Support"
repos["ansible-2.9-for-rhel-8-x86_64-rpms"]="Red Hat Ansible Engine 2.9 for RHEL 8 x86_64 (RPMs)"
repos["ansible-2-for-rhel-8-x86_64-rpms"]="Red Hat Ansible Engine 2 for RHEL 8 x86_64 (RPMs)"
repos["advanced-virt-for-rhel-8-x86_64-rpms"]="Advanced Virtualization for RHEL 8 x86_64 (RPMs)"
repos["satellite-tools-6.5-for-rhel-8-x86_64-rpms"]="Red Hat Satellite Tools for RHEL 8 Server RPMs x86_64"
repos["openstack-16.1-for-rhel-8-x86_64-rpms"]="Red Hat OpenStack Platform 16.1 for RHEL 8 (RPMs)"
repos["fast-datapath-for-rhel-8-x86_64-rpms"]="Red Hat Fast Datapath for RHEL 8 (RPMS)"
repos["rhceph-4-tools-for-rhel-8-x86_64-rpms"]="Red Hat Ceph for RHEL 8 (RPMS)"


declare -A baseurl_dir
baseurl_dir["rhel-8-for-x86_64-baseos-rpms"]=base
baseurl_dir["rhel-8-for-x86_64-appstream-rpms"]=appstream
baseurl_dir["rhel-8-for-x86_64-highavailability-rpms"]=ha
baseurl_dir["ansible-2.9-for-rhel-8-x86_64-rpms"]=ansible
baseurl_dir["ansible-2-for-rhel-8-x86_64-rpms"]=ansible
baseurl_dir["advanced-virt-for-rhel-8-x86_64-rpms"]=virt
baseurl_dir["satellite-tools-6.5-for-rhel-8-x86_64-rpms"]=satellite
baseurl_dir["openstack-16.1-for-rhel-8-x86_64-rpms"]=openstack
baseurl_dir["fast-datapath-for-rhel-8-x86_64-rpms"]=datapath
baseurl_dir["rhceph-4-tools-for-rhel-8-x86_64-rpms"]=ceph


#Generate repo file
if [ "$1" != "" ]; then
    echo ======== Created file $1. Put it into /etc/yum.repos.d/SOMETHING.repo  =========
    echo
    echo -n > $1 || true
    for repo in ${!repos[@]}; do
        echo "[$repo]" | tee -a $1
        echo name = ${repos[${repo}]} | tee -a $1
        echo baseurl = ${baseurl_prefix}/${baseurl_dir[${repo}]}/${repo} | tee -a $1
        echo enabled = 1 | tee -a $1
        echo | tee -a $1
    done
    exit
fi

#Updating repositories
mkdir -p /var/www/html/repos/{ansible,appstream,base,datapath,openstack,ha,satellite,virt}
for repo in ${!repos[@]}; do
    reposync  -p /var/www/html/repos/${baseurl_dir[${repo}]} --download-metadata --repo=${repo}
done
