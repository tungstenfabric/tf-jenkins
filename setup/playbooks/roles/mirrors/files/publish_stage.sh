#!/bin/bash

[ $# -ne 1 ] && exit 1

declare -A REPOS=( \
    ["centos7"]="centos7 yum7" \
    ["rhel7"]="rhel7 ubi7" \
    ["rhel8"]="rhel8 ubi8" \
    ["ubuntu18"]="ubuntu18" \
    ["ubuntu20"]="ubuntu20" \
)

for repo in ${REPOS[$1]} ; do
    echo "INFO: publish repo $repo for dist $1"
    BASEDIR=/var/local/mirror/repos/${repo}
    pushd ${BASEDIR}
    NEWLATEST=$(readlink stage)
    rm -f latest || /bin/true
    ln -s ${NEWLATEST} latest
    popd
done
