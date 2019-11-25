#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

echo 'INFO: Deploy k8s for manifests job'

rsync -a -e "ssh $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

cat <<EOF | ssh $SSH_OPTIONS -t $IMAGE_SSH_USER@$instance_ip
export PATH=\$PATH:/usr/sbin
cd src/tungstenfabric/tf-devstack/k8s_manifests
ORCHESTRATOR=kubernetes ./run.sh platform
EOF
