#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/common.sh

[ -f $my_dir/rhel_account ] && source $my_dir/rhel-account

MIRROR_REGISTRY="rhel7-mirrors.tf-jenkins.progmaticlab.com:5000"

REDHAT_REGISTRY="registry.access.redhat.com"
UBI_NAMESPACE="ubi7"
TAG='latest'

function sync_container() {
  local s=$REDHAT_REGISTRY/$c
  local d=$MIRROR_REGISTRY/$c
  sudo docker pull $s && \
    sudo docker tag $s $d && \
    sudo docker push $d
}

ubi_containers=(\
ubi \
)

all_containers+=$(printf "${UBI_NAMESPACE}/%s:$TAG " "${ubi_containers[@]}")

res=0
for c in ${all_containers} ; do
  echo "INFO: start sync $c"
  sync_container $c || res=1
done

if [[ $res != 0 ]] ; then
  echo "ERROR: sync failed"
  exit 1
fi

echo "INFO: sync succeeded"
