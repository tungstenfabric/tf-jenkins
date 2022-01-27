#!/bin/bash -eE
set -o pipefail

# Worker is permanent. 
[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/definitions"

echo "($date) INFO: Running cleanup.sh"
ssh -i $WORKER_SSH_KEY $SSH_OPTS $IMAGE_SSH_USER@$instance_ip "/root/cleanup.sh"

