#!/bin/bash -ex


# this scripts is for manual update of contrail tpc on nexus agains public juniper tpc

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

for f in $(find . -type f -name "*.rpm" | sed 's/^\.\///g'); do 
  curl -s -u admin:bluemoonbigsun --upload-file $f http://pnexus.sytes.net/repository/yum-tpc-source/$f
done

popd