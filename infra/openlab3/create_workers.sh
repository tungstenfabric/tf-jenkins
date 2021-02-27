#!/bin/bash -eE
set -o pipefail

# Currently only one worker can be created.

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/definitions"

ssh $SSH_OPTS $IMAGE_SSH_USER@$instance_ip "sudo rm -rf .tf src"

stackrc_file=${stackrc_file:-"stackrc.$JOB_NAME.env"}
echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$stackrc_file"
echo "export instance_ip=$instance_ip" >> "$stackrc_file"
source "$stackrc_file"
