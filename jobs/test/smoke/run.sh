#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: Test smoke started"

bash -c "\
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin

printf '%*s\n' 120 | tr ' ' '='
sudo contrail-status
printf '%*s\n' 120 | tr ' ' '='
sudo docker ps -a
printf '%*s\n' 120 | tr ' ' '='
sudo docker images
printf '%*s\n' 120 | tr ' ' '*'
ps ax -H
printf '%*s\n' 120 | tr ' ' '*'

export WORKSPACE=\$HOME
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
cd src/tungstenfabric/tf-test/smoke-test
ORCHESTRATOR=$ORCHESTRATOR ./run.sh || res=1
echo "INFO: Test smoke finished"
exit \$res
EOF
"
