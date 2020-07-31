#!/bin/bash -ex

# this scripts is for manual update of contrail tpc on nexus agains public juniper tpc

filter="${1}"

if [ -z "$filter" ]; then
  echo "ERROR: provide filter as command line argument to regexp required packages"
  exit -1
fi

[ -z "$nexus_admin_password" ] && {
  echo "ERROR: provide nexus_admin_password env variable with admin password"
  exit -1
}

# make disabled tpc poiting to juniper
cat << EOF | sudo tee /etc/yum.repos.d/external-tpc.repo 
[external-tpc]
name = External TPC Contrail repo
baseurl = http://148.251.5.90/tpc/
enabled = 0
gpgcheck = 0
EOF

stor=$(mktemp -d)

pushd $stor
yumdownloader --disablerepo=* --enablerepo="external-tpc" *

for f in $(find . -type f -name "*.rpm" | grep "$filter" | sed 's/^\.\///g'); do 
  curl -s -u admin:$nexus_admin_password --upload-file $f http://nexus.jenkins.progmaticlab.com/repository/yum-tpc-binary/$f
done

popd