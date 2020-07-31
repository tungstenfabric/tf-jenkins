#!/bin/bash -x


my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/common.sh

repos="rhel-7-server-ose-3.11-rpms rhel-7-fast-datapath-rpms rhel-7-server-ansible-2.6-rpms"
update_repos $repos
