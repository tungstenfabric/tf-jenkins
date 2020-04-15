#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
create_env_file="$WORKSPACE/stackrc.$JOB_NAME.env"

cd src/tungstenfabric/tf-devstack/rhosp/providers/vexx
vexxrc="$create_env_file" ./cleanup.sh
