#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" {$WORKSPACE/src,$my_dir/update*.sh} $IMAGE_SSH_USER@$instance_ip:./

if [[ "$ARTIFACT_TYPE" == 'THIRD_PARTY' ]] ; then
  update_func="./update_third_party.sh"
elif [[ "$ARTIFACT_TYPE" == 'SANITY_IMAGES' ]] ; then
  update_func="./update_sanity_images.sh"
fi

echo "INFO: Update artifacts started"
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export TPC_REPO_USER=$TPC_REPO_USER
export TPC_REPO_PASS=$TPC_REPO_PASS
export REPO_SOURCE=http://tf-nexus.progmaticlab.com/repository

$update_func
EOF

echo "INFO: Update artifacts finished"
