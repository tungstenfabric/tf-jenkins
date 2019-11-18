#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE="$WORKSPACE/stackrc"
source $ENV_FILE
DEPLOYMENT=$(echo ${JOB_NAME} | cut -d '-' -f 2)

rsync -e "ssh $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./
ssh $SSH_OPTIONS -t $IMAGE_SSH_USER@$instance_ip \
    "export PATH=\$PATH:/usr/sbin && cd src/tungstenfabric/tf-devstack/$DEPLOYMENT && ./startup.sh"
