#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ -z ${REPOS_TYPE} ]]; then
   echo "REPOS_TYPE is not defined. Exit"
   exit 1
fi

[ -f $my_dir/${REPOS_TYPE}.env ] || exit 1
source $my_dir/${REPOS_TYPE}.env

MIRROR_REGISTRY=${MIRROR_REGISTRY:-"tf-mirrors.progmaticlab.com:5005"}

function retain_container() {
  local c=$1
  local s=$MIRROR_REGISTRY/$c
  local d=$(echo $MIRROR_REGISTRY/$c | sed s/${REDHAT_TAG}$/${RETAIN_TAG}/)
  echo "INFO: source: $s"
  echo "INFO: destination: $d"
  sudo docker pull $s && \
    sudo docker tag $s $d && \
    sudo docker push $d
}

function publish_container() {
  local c=$1
  local s=$MIRROR_REGISTRY/$c
  local d=$(echo $MIRROR_REGISTRY/$c | sed s/${STAGE_TAG}$/${REDHAT_TAG}/)
  echo "INFO: source: $s"
  echo "INFO: destination: $d"
  sudo docker pull $s && \
    sudo docker tag $s $d && \
    sudo docker push $d
}

all_stage_images+=$(printf "${RHOSP_NAMESPACE}/%s:$STAGE_TAG " "${rhosp_images[@]}")
all_stage_images+=$(printf "${CEPH_NAMESPACE}/%s " "${ceph_images[@]}")

all_stable_images+=$(printf "${RHOSP_NAMESPACE}/%s:$REDHAT_TAG " "${rhosp_images[@]}")
all_stable_images+=$(printf "${CEPH_NAMESPACE}/%s " "${ceph_images[@]}")



res=0

for c in ${all_stable_images} ; do
  echo "INFO: start retain $c"
  retain_container $c || res=1
done

echo "INFO: retaining succeeded"

for c in ${all_stage_images} ; do
  echo "INFO: start publish $c"
  publish_container $c || res=1
done

if [[ $res != 0 ]] ; then
  echo "ERROR: publish failed"
  exit 1
fi

echo "INFO: publish succeeded"
