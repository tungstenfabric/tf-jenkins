#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

case "${CHECK}" in:
  "centos7")
    REPOS='mirror-base.repo mirror-epel.repo'
    ;;
  *)
    REPOS=''
    ;;
esac

for repofile in $REPOS; do
  sed 's|/latest/|/stage/|g' < ${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/$repofile > $repofile
done
