#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

if [[ "$CLOUD" == 'maas' ]] ; then
  if [[ "$SLAVE" != 'vexxhost' ]]; then
    echo "ERROR: current maas cloud works only for vexxhost slave"
    exit 1
  fi
  "$my_dir/create_workers_openlab.sh"
else
  "$my_dir/../common/create_workers.sh"
fi
