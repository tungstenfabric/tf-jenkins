#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


if [[ -n "$JUMPHOST" ]]; then
    source "$my_dir/../../infra/${JUMPHOST}/definitions"
    "$my_dir/../../infra/${JUMPHOST}/create_workers.sh"
else
    source "$my_dir/definitions"
    "$my_dir/../../infra/${SLAVE}/create_workers.sh"
fi
