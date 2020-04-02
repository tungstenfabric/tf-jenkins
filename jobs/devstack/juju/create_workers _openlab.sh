#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

#source "$my_dir/definitions"
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS -p 30002 -i ${OPENLAB2_SSH_KEY} ${OPENLAB2_USER_NAME}@openlab.tf-jenkins.progmaticlab.com || res=1
[ "${DEBUG,,}" == "true" ] && set -x
export BUILD_TAG=$BUILD_TAG
export PATH=\$PATH:/usr/sbin
virsh destroy vm-maas || /bin/true
virsh undefine vm-maas || /bin/true
rm -f vm-maas || /bin/true
virt-clone --original ubuntu18 --name vm-maas --auto-clone --file vm-maas
sleep 30
echo "VM is spinned"
EOF
# exit $res
exit 1
