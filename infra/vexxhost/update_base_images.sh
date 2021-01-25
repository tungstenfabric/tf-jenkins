#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

# Note: Base images centos8 rhel7 rhel8 must be updated manually.
# The image name should follow the example: base-rhel8-202012321201.

# Get images
if [[ ${IMAGE_TYPE^^} == 'ALL' || ${IMAGE_TYPE^^} == 'CENTOS7' ]]
  curl -LOs "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2.xz"
  xz --decompress CentOS-7-x86_64-GenericCloud.qcow2.xz
  openstack image create --disk-format qcow2 --tag centos7 --file CentOS-7-x86_64-GenericCloud.qcow2 base-centos7-$(date +%Y%m%d%H%M)
fi

if [[ ${IMAGE_TYPE^^} == 'ALL' || ${IMAGE_TYPE^^} == 'UBUNTU18' ]]
  curl -LOs "https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img"
  curl -Ls "https://cloud-images.ubuntu.com/bionic/current/SHA256SUMS" -o ubuntu18-SHA256SUMS
  sha256sum -c ubuntu18-SHA256SUMS --ignore-missing --status
  openstack image create --disk-format qcow2 --tag ubuntu18 --file bionic-server-cloudimg-amd64.img base-ubuntu18-$(date +%Y%m%d%H%M)
fi

# Remove previous images
# this code leaves 4 latest images - so it can be run always
IMAGES_LIST=$(openstack image list -c Name -f value | grep "^base-")
OS_NAMES=$(echo "$IMAGES_LIST" | awk -F "-" '{print $2}' | sort | uniq)

for o in $OS_NAMES; do
  OLD_IMAGES=$(echo "$IMAGES_LIST" | grep "$o" | sort -nr | tail -n +4)
  for i in $OLD_IMAGES; do
    openstack image delete $i
  done
done
