#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$WORKSPACE/global.env"
if [ -e "$WORKSPACE/build.env" ] ; then 
  source "$WORKSPACE/build.env"
fi
if [ -e "$WORKSPACE/stackrc.$JOB_NAME.env" ] ; then
  source "$WORKSPACE/stackrc.$JOB_NAME.env"
fi

ENVIRONMENT_OS=${ENVIRONMENT_OS:-'rhel7'}
OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
echo "INFO: register rhel system"
sudo subscription-manager register --username "$RHEL_USER" --password "$RHEL_PASSWORD"

echo "INFO: attach pool $RHEL_POOL_ID"
sudo subscription-manager attach --pool $RHEL_POOL_ID

[ "${DEBUG,,}" == "true" ] && set -x

declare -A os_repos_map=( ['newton']='10' \
                          ['ocata']='11' \
                          ['pike']='12' \
                          ['queens']='13' \
                          ['rocky']='14' \
                          ['stein']='15' \
                          ['train']='16' )

rhel_os_repo_num=${os_repos_map["${OPENSTACK_VERSION,,}"]}
if [[ "${ENVIRONMENT_OS,,}" != 'rhel8' ]] ; then
  sudo subscription-manager repos --enable=rhel-7-server-rpms \
                                  --enable=rhel-7-server-extras-rpms \
                                  --enable=rhel-7-server-optional-rpms \
                                  --enable=rhel-7-server-openstack-${rhel_os_repo_num}-rpms \
                                  --enable=rhel-7-server-openstack-${rhel_os_repo_num}-devtools-rpms
else
  # TODO: enable openstack repos?
  sudo subscription-manager repos --enable=rhel-8-for-x86_64-baseos-rpms \
                                  --enable=rhel-8-for-x86_64-appstream-rpms
fi
EOF
