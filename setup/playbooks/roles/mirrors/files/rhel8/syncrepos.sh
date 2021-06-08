#!/bin/bash -e

REPOS_RH8=(rhel-8-for-x86_64-appstream-rpms rhel-8-for-x86_64-baseos-rpms rhel-8-for-x86_64-highavailability-rpms ansible-2.9-for-rhel-8-x86_64-rpms ansible-2-for-rhel-8-x86_64-rpms advanced-virt-for-rhel-8-x86_64-rpms satellite-tools-6.5-for-rhel-8-x86_64-rpms openstack-16.1-for-rhel-8-x86_64-rpms fast-datapath-for-rhel-8-x86_64-rpms rhceph-4-tools-for-rhel-8-x86_64-rpms)
REPOS_UBI8=(ubi-8-appstream ubi-8-baseos ubi-8-codeready-builder)
MIRRORDIR=/repos
DATE=$(date +"%Y%m%d")

function unregister_and_exit() {
  subscription-manager unregister
  exit
}

function retry() {
  local i
  for ((i=0; i<5; ++i)) ; do
    if $@ ; then
      break
    fi
    echo "COMMAND FAILED: $@" 
    echo "RETRYING COMMAND (time=$i out of 5)"
  done
  if [[ $i == 5 ]]; then
    echo "COMMAND FAILED AFTER 5 tries: $@"
    echo ABORTING
    exit 1
  fi
}

if [[ ! -z ${RHEL_USER+x} && ! -z ${RHEL_PASSWORD+x} && ! -z ${RHEL_POOL_ID+x} ]]; then
  subscription-manager register --name=rhel8repomirror --username=$RHEL_USER --password=$RHEL_PASSWORD
else
  echo "No RedHat subscription credentials provided, exiting"
  exit 1
fi

trap unregister_and_exit EXIT
subscription-manager attach --pool=$RHEL_POOL_ID

#Fix release to 8.2 for RHOSP16
subscription-manager release --set=8.2

yum repolist
yum install -y yum-utils createrepo

for repo in "rhel8" "ubi8" ; do
  if [ ! -d ${MIRRORDIR}/$repo/${DATE} ]; then
    mkdir -p ${MIRRORDIR}/$repo/${DATE}
    if [ -d ${MIRRORDIR}/$repo/latest ]; then
      cp -R ${MIRRORDIR}/$repo/latest/* ${MIRRORDIR}/$repo/${DATE}/
    fi
  fi
done

for r in ${REPOS_RH8[@]}; do
  subscription-manager repos --enable=${r}
  retry reposync --repoid=${r} --download-metadata --downloadcomps --download-path=${MIRRORDIR}/rhel8/${DATE}
  #createrepo -v ${MIRRORDIR}/rhel8/${DATE}/${r}/
done

for r in ${REPOS_UBI8[@]}; do
  reposync --repoid=${r} --download-metadata --downloadcomps --download-path=${MIRRORDIR}/ubi8/${DATE}
  #createrepo -v ${MIRRORDIR}/ubi8/${DATE}/${r}/
done

for repo in "rhel8" "ubi8" ; do
  pushd ${MIRRORDIR}/$repo
  rm -f stage
  ln -s ${DATE} stage
  popd
done
