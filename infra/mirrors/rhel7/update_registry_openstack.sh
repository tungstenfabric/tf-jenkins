#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/common.sh

[ -f $my_dir/rhel_account ] && source $my_dir/rhel-account

MIRROR_REGISTRY="rhel7-mirrors.tf-jenkins.progmaticlab.com:5000"

REDHAT_REGISTRY="registry.redhat.io"
RHOSP_NAMESPACE="rhosp13"
CEPH_NAMESPACE="rhceph"
TAG='13.0'

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

rhosp_containers=(\
openstack-aodh-api \
openstack-aodh-evaluator \
openstack-aodh-listener \
openstack-aodh-notifier \
openstack-ceilometer-central \
openstack-ceilometer-compute \
openstack-ceilometer-notification \
openstack-cinder-api \
openstack-cinder-scheduler \
openstack-cinder-volume \
openstack-cron \
openstack-glance-api \
openstack-gnocchi-api \
openstack-gnocchi-metricd \
openstack-gnocchi-statsd \
openstack-haproxy \
openstack-heat-api-cfn \
openstack-heat-api \
openstack-heat-engine \
openstack-horizon \
openstack-iscsid \
openstack-keystone \
openstack-mariadb \
openstack-memcached \
openstack-neutron-dhcp-agent \
openstack-neutron-l3-agent \
openstack-neutron-metadata-agent \
openstack-neutron-openvswitch-agent \
openstack-neutron-server \
openstack-nova-api \
openstack-nova-api \
openstack-nova-compute \
openstack-nova-conductor \
openstack-nova-consoleauth \
openstack-nova-libvirt \
openstack-nova-novncproxy \
openstack-nova-placement-api \
openstack-nova-scheduler \
openstack-panko-api \
openstack-rabbitmq \
openstack-redis \
openstack-swift-account \
openstack-swift-container \
openstack-swift-object \
openstack-swift-proxy-server \
)

ceph_containers=(rhceph-3-rhel7:3)

all_containers+=$(printf "${RHOSP_NAMESPACE}/%s:$TAG " "${rhosp_containers[@]}")
all_containers+=$(printf "${CEPH_NAMESPACE}/%s " "${ceph_containers[@]}")

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
