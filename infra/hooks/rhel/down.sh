#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

instance_ip=$1

# TODO: think about IMAGE_SSH_USER. it's not available in cleanup_stalled_workers - IMAGE_SSH_USER will be undefined...
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
sudo subscription-manager unregister
EOF
