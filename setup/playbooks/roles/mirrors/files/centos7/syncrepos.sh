#!/bin/bash -e

REPOS_CENTOS7=(base centosplus extras updates)
REPOS_YUM7=(centos-openstack-queens dockerrepo epel google-chrome k8s)
MIRRORDIR=/repos
DATE=$(date +"%Y%m%d")

for repo in "centos7" "yum7" ; do
  if [ ! -d ${MIRRORDIR}/$repo/${DATE} ]; then
    mkdir -p ${MIRRORDIR}/$repo/${DATE}
    if [ -d ${MIRRORDIR}/$repo/latest ]; then
      cp -R ${MIRRORDIR}/$repo/latest/* ${MIRRORDIR}/$repo/${DATE}/
    fi
  fi
done

for r in ${REPOS_CENTOS7[@]}; do
  reposync -l --repoid=${r} --download-metadata --downloadcomps --download_path=${MIRRORDIR}/centos7/${DATE}
  createrepo -v ${MIRRORDIR}/centos7/${DATE}/${r}/
done

for r in ${REPOS_YUM7[@]}; do
  reposync -l --repoid=${r} --download-metadata --downloadcomps --download_path=${MIRRORDIR}/yum7/${DATE}
  createrepo -v ${MIRRORDIR}/yum7/${DATE}/${r}/
done

for repo in "centos7" "yum7" ; do
  pushd ${MIRRORDIR}/$repo
  rm -f stage
  ln -s ${DATE} stage
  popd
done
