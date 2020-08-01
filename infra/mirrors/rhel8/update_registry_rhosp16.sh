#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

#source $my_dir/common.sh

[ -f $my_dir/rhel-account ] && source $my_dir/rhel-account

MIRROR_REGISTRY="rhel8-mirrors.tf-jenkins.progmaticlab.com:5000"

REDHAT_REGISTRY="registry.redhat.io"
RHOSP_NAMESPACE="rhosp-rhel8"
TAG='16.1'

function sync_container() {
  local s=$REDHAT_REGISTRY/$c
  local d=$MIRROR_REGISTRY/$c
  sudo podman pull $s && \
    sudo podman tag $s $d && \
    sudo podman push $d
}

if [[ -n "$RHEL_USER" && "$RHEL_PASSWORD" ]] ; then
  echo "INFO: logi to docker registry $REDHAT_REGISTRY"
  sudo podman login -u $RHEL_USER -p $RHEL_PASSWORD "https://$REDHAT_REGISTRY" || {
    echo "ERROR: failed to login "
  }
fi

rhosp_images=(
openstack-cinder-api
openstack-cinder-scheduler
openstack-cinder-volume
openstack-cron
openstack-glance-api
openstack-haproxy
openstack-heat-api
openstack-heat-api-cfn
openstack-heat-engine
openstack-horizon
openstack-ironic-api
openstack-ironic-conductor
openstack-ironic-inspector
openstack-ironic-neutron-agent
openstack-ironic-pxe
openstack-iscsid
openstack-keepalived
openstack-keystone
openstack-mariadb
openstack-memcached
openstack-mistral-api
openstack-mistral-engine
openstack-mistral-event-engine
openstack-mistral-executor
openstack-neutron-dhcp-agent
openstack-neutron-l3-agent
openstack-neutron-openvswitch-agent
openstack-neutron-server
openstack-neutron-server-ovn
openstack-nova-api
openstack-nova-compute
openstack-nova-compute-ironic
openstack-nova-conductor
openstack-nova-libvirt
openstack-nova-novncproxy
openstack-nova-scheduler
openstack-placement-api
openstack-rabbitmq
openstack-redis
openstack-swift-account
openstack-swift-container
openstack-swift-object
openstack-swift-proxy-server
openstack-tempest
openstack-zaqar-wsgi
)

all_containers+=$(printf "${RHOSP_NAMESPACE}/%s:$TAG " "${rhosp_images[@]}")


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
