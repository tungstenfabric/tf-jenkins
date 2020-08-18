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
source \$HOME/$CLOUD.vars || /bin/true
export JUJU_CONTROLLER_NODES="$JUJU_CONTROLLER_NODES"
EOF
}
export -f add_deployrc

${my_dir}/../common/deploy_platform.sh juju
