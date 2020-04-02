#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
touch "$ENV_FILE"
echo "export ENVIRONMENT_OS=ubuntu18" >> "$ENV_FILE"
echo "export IMAGE_SSH_USER=jenkins" >> "$ENV_FILE"
echo "export instance_ip=192.168.51.5" >> "$ENV_FILE"
echo "export SSH_EXTRA_OPTIONS=$SSH_EXTRA_OPTIONS" >> "$ENV_FILE"

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS -p 30002 -i $OPENLAB2_SSH_KEY jenkins@openlab.tf-jenkins.progmaticlab.com
[ "${DEBUG,,}" == "true" ] && set -x
export BUILD_TAG=$BUILD_TAG
export PATH=\$PATH:/usr/sbin
virsh destroy vm-maas || /bin/true
virsh undefine vm-maas || /bin/true
rm -f vm-maas
virt-clone --original ubuntu18 --name vm-maas --auto-clone --file vm-maas
virsh start vm-maas
echo "VM is spinned"
EOF

source "$my_dir/definitions"

timeout 300 bash -c "\
while /bin/true ; do \
  ssh -i $OPENLAB2_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip 'uname -a' && break ; \
  sleep 10 ; \
done"
