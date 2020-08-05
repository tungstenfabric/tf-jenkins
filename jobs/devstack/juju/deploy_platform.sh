#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

export CLOUD=${CLOUD:-"local"}

function add_deployrc() {
  local file="$1"
  cat <<EOF >> "$file"
export CLOUD="$CLOUD"
export MAAS_ENDPOINT="$MAAS_ENDPOINT"
export MAAS_API_KEY="$MAAS_API_KEY"
export VIRTUAL_IPS="$VIRTUAL_IPS"
export JUJU_CONTROLLER_NODES="$JUJU_CONTROLLER_NODES"
EOF
}
export -f add_deployrc

${my_dir}/../common/deploy_platform.sh juju
