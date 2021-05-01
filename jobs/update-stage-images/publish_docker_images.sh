#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ -z ${REPOS_TYPE} ]]; then
  echo "REPOS_TYPE is not defined. Exit"
  exit 1
fi

[ -f $my_dir/${REPOS_TYPE}.env ] || exit 1
source $my_dir/${REPOS_TYPE}.env

MIRROR_REGISTRY=${MIRROR_REGISTRY:-"tf-mirrors.$CI_DOMAIN:5005"}

function tag_container() {
  local c=$1
  local orig_tag=$2
  local new_tag=$3
  local s=$MIRROR_REGISTRY/$c
  local d=$(echo $MIRROR_REGISTRY/$c | sed s/${orig_tag}$/${new_tag}/)
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
  tag_container $c $REDHAT_TAG $RETAIN_TAG || /bin/true
done

if [[ -n "$UBI_REDHAT_REGISTRY" && "$UBI_NAMESPACE" && "$UBI_STABLE_TAG" && $UBI_STAGE_TAG ]] ; then
  ubi_stable_images+=$(printf "${UBI_NAMESPACE}/%s:$UBI_STABLE_TAG " "${ubi_images[@]}")
  for c in ${ubi_stable_images} ; do
    echo "INFO: ubi start retain $c"
    tag_container $c $UBI_STABLE_TAG $UBI_RETAIN_TAG || /bin/true
  done
fi

echo "INFO: retaining succeeded"

for c in ${all_stage_images} ; do
  echo "INFO: start publish $c"
  tag_container $c $STAGE_TAG $REDHAT_TAG || res=1
done

if [[ -n "$UBI_REDHAT_REGISTRY" && "$UBI_NAMESPACE" && "$UBI_STABLE_TAG" && $UBI_STAGE_TAG ]] ; then
  ubi_stage_images+=$(printf "${UBI_NAMESPACE}/%s:$UBI_STAGE_TAG " "${ubi_images[@]}")
  for c in ${ubi_stage_images} ; do
    echo "INFO: ubi start publish $c"
    tag_container $c $UBI_STAGE_TAG $UBI_STABLE_TAG || res=1
  done
fi

if [[ $res != 0 ]] ; then
  echo "ERROR: publish failed"
  exit 1
fi

echo "INFO: publish succeeded"
