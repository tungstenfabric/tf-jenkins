#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ -z ${REPOS_TYPE} ]]; then
   echo "REPOS_TYPE is not defined. Exit"
   exit 1
fi

[ -f $my_dir/${REPOS_TYPE}.env ] || exit 1 
source $my_dir/${REPOS_TYPE}.env


[ -f $my_dir/rhel-account ] && source $my_dir/rhel-account

MIRROR_REGISTRY=${MIRROR_REGISTRY:-"tf-mirrors.progmaticlab.com:5005"}

function retry() {
  local i
  for ((i=0; i<5; ++i)) ; do
    if $@ ; then
      break
    fi
    echo "COMMAND FAILED: $@" 
    echo "RETRYING COMMAND (time=$i out of 5)"
    sleep 5
  done
  if [[ $i == 5 ]]; then
    echo ERROR. COMMAND FAILE AFTER 5 retries: $@
    exit 1
  fi
}

function sync_container() {
  local c=$1
  local s=$REDHAT_REGISTRY/$c
  local d=$(echo $MIRROR_REGISTRY/$c | sed s/${REDHAT_TAG}$/${STAGE_TAG}/)
  echo "INFO: destination: $d"
  retry sudo docker pull $s && \
    sudo docker tag $s $d && \
    sudo docker push $d
}

if [[ -n "$RHEL_USER" && "$RHEL_PASSWORD" ]] ; then
  echo "INFO: login to docker registry $REDHAT_REGISTRY"
  sudo docker login -u $RHEL_USER -p $RHEL_PASSWORD "https://$REDHAT_REGISTRY" || {
    echo "ERROR: failed to login "
  }
else
  echo "ERROR: No RedHat credentials. Please define variables RHEL_USER and RHEL_PASSWORD. Exiting..."
  exit 1
fi

all_images+=$(printf "${RHOSP_NAMESPACE}/%s:$REDHAT_TAG " "${rhosp_images[@]}")
all_images+=$(printf "${CEPH_NAMESPACE}/%s " "${ceph_images[@]}")

res=0
for c in ${all_images} ; do
  echo "INFO: start sync $c"
  sync_container $c || res=1
done

if [[ $res != 0 ]] ; then
  echo "ERROR: sync failed"
  exit 1
fi

echo "INFO: sync succeeded"
