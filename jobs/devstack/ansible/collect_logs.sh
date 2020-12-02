#!/bin/bash -e
set -o pipefail

set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

${my_dir}/../common/collect_logs.sh ansible
