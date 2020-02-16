#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
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
echo "INFO: Update ubuntu OS"
echo "APT::Acquire::Retries \"10\";" | sudo tee /etc/apt/apt.conf.d/80-retries
sudo cp -f /usr/share/unattended-upgrades/20auto-upgrades-disabled /etc/apt/apt.conf.d/ || /bin/true
EOF
