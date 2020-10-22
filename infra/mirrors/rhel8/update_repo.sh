#!/bin/bash -e


#mkdir -p /var/www/html/repos/{ansible,appstream,base,datapath,openstack,ha,satellite}
#
#reposync  -p /var/www/html/repos/ansible --download-metadata --repo=ansible-2-for-rhel-8-x86_64-rpms
#reposync  -p /var/www/html/repos/appstream --download-metadata --repo=rhel-8-for-x86_64-appstream-rpms
#reposync  -p /var/www/html/repos/base --download-metadata --repo=rhel-8-for-x86_64-baseos-rpms
#reposync  -p /var/www/html/repos/datapath --download-metadata  --repo=fast-datapath-for-rhel-8-x86_64-rpms 
#reposync  -p /var/www/html/repos/openstack --download-metadata  --repo=openstack-16.1-for-rhel-8-x86_64-rpms
#reposync  -p /var/www/html/repos/ha --download-metadata  --repo=rhel-8-for-x86_64-highavailability-rpms
#reposync  -p /var/www/html/repos/satellite --download-metadata  --repo=satellite-tools-6.5-for-rhel-8-x86_64-rpms

baseurl_prefix=${BASEURL_PREFIX:-"http://10.10.50.3/repos/"} 
declare -A repos
#repos["rhel-8-for-x86_64-baseos-eus-rpms"]="Red Hat Enterprise Linux 8 for x86_64 - BaseOS (RPMs) Extended Update Support (EUS)"
repos["rhel-8-for-x86_64-baseos-rpms"]="Red Hat Enterprise Linux 8 for x86_64 - BaseOS (RPMs) Extended Update Support"
#repos["rhel-8-for-x86_64-appstream-eus-rpms"]="Red Hat Enterprise Linux 8 for x86_64 - AppStream (RPMs)"
repos["rhel-8-for-x86_64-appstream-rpms"]="Red Hat Enterprise Linux 8 for x86_64 - AppStream (RPMs)"
#repos["rhel-8-for-x86_64-highavailability-eus-rpms"]="Red Hat Enterprise Linux 8 for x86_64 - High Availability (RPMs) Extended Update Support (EUS)"
repos["rhel-8-for-x86_64-highavailability-rpms"]="Red Hat Enterprise Linux 8 for x86_64 - High Availability (RPMs) Extended Update Support"
repos["ansible-2.9-for-rhel-8-x86_64-rpms"]="Red Hat Ansible Engine 2.9 for RHEL 8 x86_64 (RPMs)"
repos["advanced-virt-for-rhel-8-x86_64-rpms"]="Advanced Virtualization for RHEL 8 x86_64 (RPMs)"
repos["satellite-tools-6.5-for-rhel-8-x86_64-rpms"]="Red Hat Satellite Tools for RHEL 8 Server RPMs x86_64"
repos["openstack-16.1-for-rhel-8-x86_64-rpms"]="Red Hat OpenStack Platform 16.1 for RHEL 8 (RPMs)"
repos["fast-datapath-for-rhel-8-x86_64-rpms"]="Red Hat Fast Datapath for RHEL 8 (RPMS)"

for repo in ${!repos[@]}; do
    reposync  -p /var/www/html/repos --download-metadata --repo=${repo}
done


#Generate repo file
for repo in ${!repos[@]}; do
    echo "[$repo]"
    echo name = ${repos[${repo}]}
    echo baseurl = ${baseurl_prefix}/${repo}
    echo enabled = 1
    echo
done

