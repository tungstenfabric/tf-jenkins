#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
create_env_file="stackrc.$JOB_NAME.env"
source $create_env_file

cd src/tungstenfabric/tf-devstack/rhosp/providers/vexx
./cleanup.sh

