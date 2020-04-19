#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
stackrc_file="deps.${JOB_NAME}.${JOB_RND}.env"

cd src/tungstenfabric/tf-devstack/rhosp/providers/vexx
vexxrc="${WORKSPACE}/$stackrc_file" ./cleanup.sh
