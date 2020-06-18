#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
stackrc_file=${stackrc_file:-"deps.${JOB_NAME}.${JOB_RND}.env"}
stackrc_file_path=$WORKSPACE/$stackrc_file

if [[ "$PROVIDER" == "bmc" ]]; then
    exit
fi

cd src/tungstenfabric/tf-devstack/rhosp/providers/vexx
vexxrc="$stackrc_file_path" ./cleanup.sh
