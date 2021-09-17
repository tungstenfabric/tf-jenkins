#!/bin/bash -e

REPOS_RH8=(rhel-8-for-x86_64-appstream-rpms rhel-8-for-x86_64-baseos-rpms rhel-8-for-x86_64-highavailability-rpms ansible-2.9-for-rhel-8-x86_64-rpms ansible-2-for-rhel-8-x86_64-rpms advanced-virt-for-rhel-8-x86_64-rpms satellite-tools-6.5-for-rhel-8-x86_64-rpms openstack-16.2-for-rhel-8-x86_64-rpms fast-datapath-for-rhel-8-x86_64-rpms rhceph-4-tools-for-rhel-8-x86_64-rpms)
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
    echo "ERROR: COMMAND FAILED AFTER 5 tries: $@"
    exit 1
  fi
}

if [[ -n ${RHEL_USER+x} && -n ${RHEL_PASSWORD+x} && -n ${RHEL_POOL_ID+x} ]]; then
  subscription-manager register --name=rhel84repomirror --username=$RHEL_USER --password=$RHEL_PASSWORD
else
  echo "ERROR: No RedHat subscription credentials provided, exiting"
  exit 1
fi

trap unregister_and_exit EXIT
subscription-manager attach --pool=$RHEL_POOL_ID

#Fix release to 8.4 for RHOSP16
subscription-manager release --set=8.4

yum repolist
yum install -y yum-utils createrepo

for repo in "rhel84" ; do
  if [ ! -d ${MIRRORDIR}/$repo/${DATE} ]; then
    mkdir -p ${MIRRORDIR}/$repo/${DATE}
    if [ -d ${MIRRORDIR}/$repo/latest ]; then
      echo "INFO: Copying current latest for repo $repo to stage to speed up reposync"
      cp -R ${MIRRORDIR}/$repo/latest/* ${MIRRORDIR}/$repo/${DATE}/
      echo "INFO: Copied"
    fi
  fi
done

for r in ${REPOS_RH8[@]}; do
  subscription-manager repos --enable=${r}
  retry reposync --repoid=${r} --download-metadata --downloadcomps --download-path=${MIRRORDIR}/rhel84/${DATE}
  #createrepo -v ${MIRRORDIR}/rhel84/${DATE}/${r}/
done

for repo in "rhel84"; do
  pushd ${MIRRORDIR}/$repo
  rm -f stage
  ln -s ${DATE} stage
  popd
done

