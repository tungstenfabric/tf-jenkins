#!/bin/bash -e

REPOS_CENTOS7=(base centosplus extras updates)
REPOS_YUM7=(centos-openstack-queens dockerrepo epel google-chrome)
#REPOS_UBI7=(ubi-7 ubi-7-server-debug-rpms ubi-7-server-source-rpms ubi-7-server-optional-rpms ubi-7-server-optional-debug-rpms ubi-7-server-optional-source-rpms ubi-7-server-extras-rpms ubi-7-server-extras-debug-rpms ubi-7-server-extras-source-rpms ubi-7-rhah ubi-7-rhah-debug ubi-7-rhah-source ubi-server-rhscl-7-rpms ubi-server-rhscl-7-debug-rpms ubi-server-rhscl-7-source-rpms ubi-7-server-devtools-rpms ubi-7-server-devtools-debug-rpms ubi-7-server-devtools-source-rpms)
MIRRORDIR=/repos
DATE=$(date +"%Y%m%d")

for r in ${REPOS_CENTOS7[@]}; do
  reposync -l --repoid=${r} --download-metadata --downloadcomps --download_path=${MIRRORDIR}/centos7/${DATE}
  createrepo -v ${MIRRORDIR}/centos7/${DATE}/${r}/
done

pushd ${MIRRORDIR}/centos7
rm -f stage
ln -s ${DATE} stage
popd

for r in ${REPOS_YUM7[@]}; do
  reposync -l --repoid=${r} --download-metadata --downloadcomps --download_path=${MIRRORDIR}/yum7/${DATE}
  createrepo -v ${MIRRORDIR}/yum7/${DATE}/${r}/
done

pushd ${MIRRORDIR}/yum7
rm -f stage
ln -s ${DATE} stage
popd
