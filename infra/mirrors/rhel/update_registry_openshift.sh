#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/common.sh

[ -f $my_dir/rhel_account ] && source $my_dir/rhel-account

MIRROR_REGISTRY="rhel-mirrors.tf-jenkins.progmaticlab.com:5000"
REDHAT_REGISTRY="registry.redhat.io"

RHEL_NAMESPACE="rhel7"
OPENSHIFT_NAMESPACE="openshift3"
TAG='v3.11'

#rhel
rhel_containers=( \
  etcd:3.2.22 \
)

#openshift
openshift_containers=( \
  logging-auth-proxy \
  logging-curator \
  logging-deployer \
  logging-elasticsearch \
  logging-fluentd \
  logging-kibana \
  metrics-cassandra \
  metrics-deployer \
  metrics-hawkular-metrics \
  metrics-heapster \
  node \
  openvswitch \
  ose \
  ose-cluster-monitoring-operator \
  ose-control-plane \
  ose-deployer \
  ose-docker-builder \
  ose-docker-registry \
  ose-haproxy-router \
  ose-node \
  ose-pod \
  ose-recycler \
  ose-sti-builder \
  registry-console \
)

function sync_container() {
  local s=$REDHAT_REGISTRY/$c
  local d=$MIRROR_REGISTRY/$c
  sudo docker pull $s && \
    sudo docker tag $s $d && \
    sudo docker push $d
}

if [[ -n "$RHEL_USER" && "$RHEL_PASSWORD" ]] ; then
  sudo docker login --username $RHEL_USER --password $RHEL_PASSWORD $REDHAT_REGISTRY || {
    echo "ERROR: failed to login "
  }
fi

all_containers=$(printf "${RHEL_NAMESPACE}/%s " "${rhel_containers[@]}")
all_containers+=$(printf "${OPENSHIFT_NAMESPACE}/%s:$TAG " "${openshift_containers[@]}")
jobs=""
for c in ${all_containers} ; do  
  echo "INFO: start sync $c"
  sync_container $c &
  jobs+=" $!"
done

res=0
for j in $jobs ; do
  wait $j || res=1
done

if [[ $res != 0 ]] ; then
  echo "ERROR: sync failed"
  exit 1
fi

echo "INFO: sync succeeded"
