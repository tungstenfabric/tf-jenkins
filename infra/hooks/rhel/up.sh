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

#This hook is for VEXX only
if [[ "$PROVIDER" != 'vexx' ]]; then
   echo Skipping hooks.
   exit 0
fi

ENVIRONMENT_OS=${ENVIRONMENT_OS:-'rhel7'}
OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}

rhel_ver=${ENVIRONMENT_OS,,}
os_ver=${OPENSTACK_VERSION,,}
echo "INFO: Supported rhel openstacks: ${RHEL_REPOS_MAP[@]}"
rhel_os_repo_num=${RHEL_REPOS_MAP["${os_ver}"]}
echo "INFO: Chosen for $rhel_ver and OS ${os_ver} repo number: ${rhel_os_repo_num}"

if [[ $rhel_ver == 'rhel7' ]]; then
  rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$my_dir/../../mirrors/mirror-rhel7.repo" ${IMAGE_SSH_USER}@${instance_ip}:./local.repo
elif [[ $rhel_ver == 'rhel8' ]]; then
  rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$my_dir/../../mirrors/mirror-rhel8-all.repo" ${IMAGE_SSH_USER}@${instance_ip}:./local.repo
else
  echo "ERROR: unsupported RHEL version = $rhel_ver"
  exit 1
fi

rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$my_dir/distribute_local_repos.sh" ${IMAGE_SSH_USER}@${instance_ip}:./distribute_local_repos.sh

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
sudo cp -f ./local.repo /etc/yum.repos.d/local.repo
./distribute_local_repos.sh
EOF
