#!/bin/bash -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/common.sh

repos="rhel-7-server-rpms rhel-7-server-extras-rpms rhel-7-server-optional-rpms rhel-server-rhscl-7-rpms rhel-ha-for-rhel-7-server-rpms"
update_repos $repos
