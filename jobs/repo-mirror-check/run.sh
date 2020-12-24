#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

case "${CHECKREPO}" in:
  "centos7")
    REPOFILES='mirror-base.repo mirror-epel.repo google-chrome.repo mirror-docker.repo mirror-openstack.repo'
    ;;
  "rhel7")
    REPOFILES='mirror-rhel7.repo ubi.repo'
    ;;
  "ubuntu18")
    REPOFILES='ubuntu18-sources.list'
    ;;
  *)
    REPOFILES=''
    ;;
esac

for repofile in $REPOFILES; do
  sed 's|/latest/|/stage/|g' < ${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/$repofile > $repofile
done
