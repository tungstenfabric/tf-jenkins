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
openstack-aodh-api
openstack-aodh-evaluator
openstack-aodh-listener
openstack-aodh-notifier
openstack-barbican-api
openstack-barbican-keystone-listener
openstack-barbican-worker
openstack-cinder-api
openstack-cinder-backup
openstack-cinder-scheduler
openstack-cinder-volume
openstack-collectd
openstack-cron
openstack-designate-api
openstack-designate-backend-bind9
openstack-designate-central
openstack-designate-mdns
openstack-designate-producer
openstack-designate-sink
openstack-designate-worker
openstack-ec2-api
openstack-etcd
openstack-glance-api
openstack-gnocchi-api
openstack-gnocchi-metricd
openstack-gnocchi-statsd
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
openstack-manila-api
openstack-manila-scheduler
openstack-manila-share
openstack-mariadb
openstack-memcached
openstack-mistral-api
openstack-mistral-engine
openstack-mistral-event-engine
openstack-mistral-executor
openstack-multipathd
openstack-neutron-dhcp-agent
openstack-neutron-l3-agent
openstack-neutron-metadata-agent
openstack-neutron-metadata-agent-ovn
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
openstack-octavia-api
openstack-octavia-health-manager
openstack-octavia-housekeeping
openstack-octavia-worker
openstack-ovn-controller
openstack-ovn-nb-db-server
openstack-ovn-northd
openstack-ovn-sb-db-server
openstack-panko-api
openstack-placement-api
openstack-qdrouterd
openstack-rabbitmq
openstack-redis
openstack-rsyslog
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
