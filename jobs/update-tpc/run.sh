#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

TPC_REPO_NAME="yum-tpc-source-${TPC_VERSION}"
DEVENV_TAG="tpcbuild-${TPC_VERSION}"

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" {$WORKSPACE/src,$my_dir/update_tpc.sh} $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: Update tpc started (ENVIRONMENT_OS=$ENVIRONMENT_OS, DEVENV_TAG=$DEVENV_TAG, TPC_REPO_NAME=$TPC_REPO_NAME)"
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export TPC_REPO_USER=$TPC_REPO_USER
export TPC_REPO_PASS=$TPC_REPO_PASS

export REPO_SOURCE=http://nexus.$SLAVE_REGION.$CI_DOMAIN/repository/$TPC_REPO_NAME
export CONTAINER_REGISTRY=nexus.$SLAVE_REGION.$CI_DOMAIN:5101
export LINUX_DISTR=$LINUX_DISTR
export LINUX_DISTR_VER=$LINUX_DISTR_VER
export DEVENV_TAG=${DEVENV_TAG}
export CONTRAIL_DEPLOY_REGISTRY=0

export PATH=\$PATH:/usr/sbin
./update_tpc.sh
EOF
echo "INFO: Update tpc finished"
