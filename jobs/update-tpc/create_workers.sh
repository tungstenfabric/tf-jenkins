#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

echo "INFO: create worker (ENVIRONMENT_OS=$ENVIRONMENT_OS)"
"$my_dir/../../infra/${SLAVE}/create_workers.sh"
