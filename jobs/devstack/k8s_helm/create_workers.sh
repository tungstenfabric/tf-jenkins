#!/bin/bash -eE
set -o pipefail

slave_cloud=$1

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

"$my_dir/../../infra/${slave_cloud}/create_vms.sh" $CONTROLLERS_COUNT ? ?
