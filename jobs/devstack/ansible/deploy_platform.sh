#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

echo 'INFO: Deploy platform for $JOB_NAME'

# target 'platform' tries to fetch_deployer and use code from that container.
# but for gerrit's check this container will be created in hour in build job.
# as a workaround we will skip deploy platform here.
# next solution is to use tf-developer-sandbox image which was created
# by fetch job (but with different DEPLOYER_DIR)
exit 0

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG"
export PATH=\$PATH:/usr/sbin
cd src/tungstenfabric/tf-devstack/ansible
ORCHESTRATOR=$ORCHESTRATOR ./run.sh platform
EOF

echo "INFO: Deploy platform finished"
