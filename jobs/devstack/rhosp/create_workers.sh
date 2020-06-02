#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

if [[ "$SLAVE" != 'vexxhost' ]]; then
  echo "ERROR: current rhosp deploy works only for vexxhost slave"
  exit 1
fi

if [[ "$CLOUD" == 'bmc' ]] ; then
  "$my_dir/create_workers_openlab.sh"
else
  "$my_dir/create_workers_vexxhost.sh"
fi
