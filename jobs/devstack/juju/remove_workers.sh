#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
if [[ "$CLOUD" != 'maas' ]] ; then
  "$my_dir/../../../infra/${SLAVE}/remove_workers.sh"
fi
