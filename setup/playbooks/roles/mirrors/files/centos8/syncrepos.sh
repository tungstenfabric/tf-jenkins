#!/bin/bash -e

# TODO: add centos8 repos
REPOS_CENTOS=()
REPOS_YUM=(epel)
MIRRORDIR=/repos
DATE=$(date +"%Y%m%d")

for repo in "centos8" "yum8" ; do
  if [ ! -d ${MIRRORDIR}/$repo/${DATE} ]; then
    mkdir -p ${MIRRORDIR}/$repo/${DATE}
    if [ -d ${MIRRORDIR}/$repo/latest ]; then
      echo "INFO: Copying current latest for repo $repo to stage to speed up reposync"
      cp -R ${MIRRORDIR}/$repo/latest/* ${MIRRORDIR}/$repo/${DATE}/
        echo "INFO: Copied"
    fi
  fi
done

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

for r in ${REPOS_CENTOS[@]}; do
  retry reposync --repoid=${r} --download-metadata --downloadcomps --download-path=${MIRRORDIR}/centos8/${DATE}
  createrepo -v ${MIRRORDIR}/centos8/${DATE}/${r}/
done

for r in ${REPOS_YUM[@]}; do
  retry reposync --repoid=${r} --download-metadata --downloadcomps --download-path=${MIRRORDIR}/yum8/${DATE}
  createrepo -v ${MIRRORDIR}/yum8/${DATE}/${r}/
done

for repo in "centos8" "yum8" ; do
  pushd ${MIRRORDIR}/$repo
  rm -f stage
  ln -s ${DATE} stage
  popd
done
