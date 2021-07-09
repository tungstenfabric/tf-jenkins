#!/bin/bash -eE

set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$WORKSPACE/global.env"
source "$WORKSPACE/stackrc.$JOB_NAME.env" || /bin/true
source "${WORKSPACE}/deps.${JOB_NAME}.${JOB_RND}.env" || /bin/true
source "${WORKSPACE}/vars.${JOB_NAME}.${JOB_RND}.env" || /bin/true

#This hook is for openstack only
if [[ "$PROVIDER" != 'openstack' ]]; then
  echo "INFO: Skipping hooks. RHEL hooks for openstack only"
  exit 0
fi

repofile="$my_dir/../../mirrors/mirror-${ENVIRONMENT_OS}.repo"
if [[ -f $repofile ]]; then
    echo "INFO: Using repofile $repofile"
else
    echo "repofile $repofile not found. Stop"
    exit 1
fi

cat $repofile | envsubst > $WORKSPACE/local.repo
rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$WORKSPACE/local.repo" ${IMAGE_SSH_USER}@${instance_ip}:./local.repo
rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$my_dir/distribute_local_repos.sh" ${IMAGE_SSH_USER}@${instance_ip}:./distribute_local_repos.sh

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
sudo cp -f ./local.repo /etc/yum.repos.d/local.repo
./distribute_local_repos.sh
EOF
