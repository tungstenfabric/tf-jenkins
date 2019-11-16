#!/bin/bash -e

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"#!/bin/bash -e

[ "${DEBUG,,}" == "true" ] && set -x
