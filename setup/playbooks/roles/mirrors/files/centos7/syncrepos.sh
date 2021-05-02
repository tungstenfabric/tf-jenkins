#!/bin/bash -e

REPOS_CENTOS7=(base centosplus extras updates)
REPOS_YUM7=(centos-openstack-queens dockerrepo epel google-chrome k8s)
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
