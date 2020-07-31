#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" {$WORKSPACE/src,$WORKSPACE/update_tpc.sh} $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: Update tpc started"
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export REPO_SOURCE=$REPO_SOURCE
export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
export DEVENV_TAG=$DEVENV_TAG
export TPC_REPO_USER=$TPC_REPO_USER
export TPC_REPO_PASS=$TPC_REPO_PASS
export PATH=\$PATH:/usr/sbin
./update_tpc.sh
EOF
echo "INFO: Update tpc finished"
