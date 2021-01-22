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

ENVIRONMENT_OS=${ENVIRONMENT_OS:-'rhel7'}
OPENSTACK_VERSION=${OPENSTACK_VERSION:-'queens'}

rhel_ver=${ENVIRONMENT_OS,,}
os_ver=${OPENSTACK_VERSION,,}
echo "INFO: Supported rhel openstacks: ${RHEL_REPOS_MAP[@]}"
rhel_os_repo_num=${RHEL_REPOS_MAP["${os_ver}"]}
echo "INFO: Chosen for $rhel_ver and OS ${os_ver} repo number: ${rhel_os_repo_num}"

source $my_dir/${rhel_ver}-up.sh


