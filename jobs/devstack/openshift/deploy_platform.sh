#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

function add_deployrc() {
  local file=$1
  cat <<EOF >> $file
export RHEL_OPENSHIFT_REGISTRY=$RHEL_OPENSHIFT_REGISTRY
sudo setenforce 0
EOF
}
export -f add_deployrc

${my_dir}/../common/deploy_platform.sh openshift
