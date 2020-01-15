#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

# Note: Base images centos8 rhel7 rhel8 must be updated manually.
# The image name should follow the example: base-rhel8-202012321201.

# Get images
curl -LOs "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2.xz"
xz --decompress CentOS-7-x86_64-GenericCloud.qcow2.xz

curl -LOs "https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img"
curl -Ls "https://cloud-images.ubuntu.com/xenial/current/SHA256SUMS" -o ubuntu16-SHA256SUMS
sha256sum -c ubuntu16-SHA256SUMS --ignore-missing --status

curl -LOs "https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img"
curl -Ls "https://cloud-images.ubuntu.com/bionic/current/SHA256SUMS" -o ubuntu18-SHA256SUMS
sha256sum -c ubuntu18-SHA256SUMS --ignore-missing --status

# Upload
openstack image create --disk-format qcow2 --tag centos7 --file CentOS-7-x86_64-GenericCloud.qcow2 base-centos7-$(date +%Y%m%d%H%M)
openstack image create --disk-format qcow2 --tag ubuntu16 --file xenial-server-cloudimg-amd64-disk1.img base-ubuntu16-$(date +%Y%m%d%H%M)
openstack image create --disk-format qcow2 --tag ubuntu18 --file bionic-server-cloudimg-amd64.img base-ubuntu18-$(date +%Y%m%d%H%M)

# Remove previous images
IMAGES_LIST=$(openstack image list -c Name -f value | grep "^base-")
OS_NAMES=$(echo "$IMAGES_LIST" | awk -F "-" '{print $2}' | sort | uniq)

for o in $OS_NAMES; do
  OLD_IMAGES=$(echo "$IMAGES_LIST" | grep "$o" | sort -nr | tail -n +4)
  for i in $OLD_IMAGES; do
    openstack image delete $i
  done
done
