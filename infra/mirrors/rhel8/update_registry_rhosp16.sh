#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

#source $my_dir/common.sh

[ -f $my_dir/rhel-account ] && source $my_dir/rhel-account

MIRROR_REGISTRY="rhel8-mirrors.tf-jenkins.progmaticlab.com:5000"

REDHAT_REGISTRY="registry.redhat.io"
#REDHAT_REGISTRY="registry.access.redhat.com"
RHOSP_NAMESPACE="rhosp-rhel8"
TAG='16.0'
#FILE_CONTAINERS='rhosp_containers_list.txt'
additional_container=(\
openstack-ironic-api \
)
rhosp13_images=(\
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

rhosp16_images=(\
openstack-heat-api-cfn \
openstack-neutron-l3-agent \
openstack-neutron-dhcp-agent \
openstack-mistral-event-engine \
openstack-nova-compute-ironic \
openstack-barbican-keystone-listener \
openstack-ironic-neutron-agent \
openstack-neutron-sriov-agent \
openstack-neutron-server-ovn \
openstack-neutron-metadata-agent \
openstack-neutron-openvswitch-agent \
openstack-octavia-health-manager \
openstack-swift-proxy-server \
openstack-aodh-notifier \
openstack-barbican-api \
openstack-barbican-worker \
openstack-ceilometer-base \
openstack-ceilometer-ipmi \
openstack-cinder-api \
openstack-glance-base \
openstack-gnocchi-api \
openstack-gnocchi-base \
openstack-glance-api \
openstack-ec2-api \
openstack-heat-api \
openstack-ironic-inspector \
openstack-ironic-api \
openstack-ironic-base \
openstack-ironic-pxe \
openstack-mistral-base \
openstack-mistral-api \
openstack-nova-base \
openstack-novajoin-notifier \
openstack-mistral-executor \
openstack-nova-scheduler \
openstack-octavia-api \
openstack-octavia-base \
openstack-nova-conductor \
openstack-octavia-housekeeping \
openstack-octavia-worker \
openstack-openvswitch-base \
openstack-nova-libvirt \
openstack-swift-base \
openstack-swift-account \
openstack-zaqar-wsgi \
openstack-aodh-api \
openstack-aodh-base \
openstack-aodh-listener \
openstack-aodh-evaluator \
openstack-barbican-base \
openstack-ceilometer-central \
openstack-ceilometer-compute \
openstack-ceilometer-notification \
openstack-cinder-backup \
openstack-cinder-base \
openstack-cinder-volume \
openstack-cinder-scheduler \
openstack-gnocchi-metricd \
openstack-heat-all \
openstack-heat-engine \
openstack-gnocchi-statsd \
openstack-heat-base \
openstack-ironic-conductor \
openstack-keystone-base \
openstack-manila-api \
openstack-manila-base \
openstack-mistral-engine \
openstack-manila-scheduler \
openstack-manila-share \
openstack-neutron-base \
openstack-nova-api \
openstack-nova-compute \
openstack-novajoin-server \
openstack-neutron-server \
openstack-novajoin-base \
openstack-nova-novncproxy \
openstack-panko-api \
openstack-ovn-northd \
openstack-ovn-base \
openstack-rsyslog-base \
openstack-panko-base \
openstack-placement-api \
openstack-ovn-controller \
openstack-swift-container \
openstack-redis-base \
openstack-placement-base \
openstack-swift-object \
openstack-zaqar-base \
openstack-dependencies \
openstack-collectd \
openstack-etcd \
openstack-keystone \
openstack-mariadb \
openstack-qdrouterd \
openstack-rabbitmq \
openstack-tempest \
openstack-base \
openstack-cron \
openstack-haproxy \
openstack-horizon \
openstack-keepalived \
openstack-iscsid \
openstack-memcached \
openstack-ovn-nb-db-server \
openstack-multipathd \
openstack-rsyslog \
openstack-redis \
openstack-neutron-metadata-agent-ovn \
openstack-ovn-sb-db-server \
)
#all_containers+=$(printf "${RHOSP_NAMESPACE}/%s:$TAG " "${rhosp13_images[@]}")
all_containers+=$(printf "${RHOSP_NAMESPACE}/%s:$TAG " "${rhosp16_images[@]}")


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
