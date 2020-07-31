#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/common.sh

[ -f $my_dir/rhel_account ] && source $my_dir/rhel-account

MIRROR_REGISTRY="rhel7-mirrors.tf-jenkins.progmaticlab.com:5000"
REDHAT_REGISTRY="registry.redhat.io"

RHEL_NAMESPACE="rhel7"
OPENSHIFT_NAMESPACE="openshift3"
TAG='v3.11.188'

#docker
docker_containers=( \
  redis:4.0.2 \
)

#rhel
rhel_containers=( \
  etcd:3.2.22 \
)

#openshift
openshift_containers=( \
  grafana \
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
  metrics-schema-installer \
  node \
  oauth-proxy \
  openvswitch \
  ose \
  ose-ansible-service-broker \
  ose-cluster-monitoring-operator \
  ose-configmap-reloader \
  ose-console \
  ose-control-plane \
  ose-deployer \
  ose-docker-builder \
  ose-docker-registry \
  ose-haproxy-router \
  ose-kube-rbac-proxy \
  ose-kube-state-metrics \
  ose-logging-elasticsearch5 \
  ose-logging-fluentd \
  ose-logging-kibana5 \
  ose-metrics-server \
  ose-node \
  ose-pod \
  ose-prometheus-config-reloader \
  ose-prometheus-operator \
  ose-recycler \
  ose-service-catalog \
  ose-sti-builder \
  ose-template-service-broker \
  ose-web-console \
  prometheus \
  prometheus-alertmanager \
  prometheus-node-exporter \
  registry-console \
)

openshift_containers_2=( \
  ose-deployer:v3.11.200 \
)

function sync_container() {
  local s=$REDHAT_REGISTRY/$c
  local d=$MIRROR_REGISTRY/$c
  sudo docker pull $s && \
    sudo docker tag $s $d && \
    sudo docker push $d
}

if [[ -n "$RHEL_USER" && "$RHEL_PASSWORD" ]] ; then
  echo "INFO: logi to docker registry $REDHAT_REGISTRY"
  sudo docker login --username $RHEL_USER --password $RHEL_PASSWORD $REDHAT_REGISTRY || {
    echo "ERROR: failed to login "
  }
fi

all_containers+=$(printf "%s " "${docker_containers[@]}")
all_containers+=$(printf "${RHEL_NAMESPACE}/%s " "${rhel_containers[@]}")
all_containers+=$(printf "${OPENSHIFT_NAMESPACE}/%s:$TAG " "${openshift_containers[@]}")
all_containers+=$(printf "${OPENSHIFT_NAMESPACE}/%s " "${openshift_containers_2[@]}")

# jobs=""
res=0
for c in ${all_containers} ; do  
  echo "INFO: start sync $c"
  sync_container $c || res=1
  # jobs+=" $!"
done

# for j in $jobs ; do
#   wait $j || res=1
# done

if [[ $res != 0 ]] ; then
  echo "ERROR: sync failed"
  exit 1
fi

echo "INFO: sync succeeded"
