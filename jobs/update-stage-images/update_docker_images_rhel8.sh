#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

[ -f $my_dir/rhel-account ] && source $my_dir/rhel-account

MIRROR_REGISTRY=${MIRROR_REGISTRY:-"tf-mirrors.progmaticlab.com:5005"}

REDHAT_REGISTRY="registry.redhat.io"
RHOSP_NAMESPACE="rhosp-rhel8"
CEPH_NAMESPACE="rhceph"

REDHAT_TAG='16.1'
LOCAL_TAG='16.1-staging'

function sync_container() {
  local c=$1
  local s=$REDHAT_REGISTRY/$c
  local d=$(echo $MIRROR_REGISTRY/$c | sed s/${REDHAT_TAG}$/${LOCAL_TAG}/)
  sudo docker pull $s && \
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

rhosp_images=(\
openstack-aodh-api \
openstack-aodh-evaluator \
openstack-aodh-listener \
openstack-aodh-notifier \
openstack-barbican-api \
openstack-barbican-keystone-listener \
openstack-barbican-worker \
openstack-cinder-api \
openstack-cinder-backup \
openstack-cinder-scheduler \
openstack-cinder-volume \
openstack-collectd \
openstack-cron \
openstack-designate-api \
openstack-designate-backend-bind9 \
openstack-designate-central \
openstack-designate-mdns \
openstack-designate-producer \
openstack-designate-sink \
openstack-designate-worker \
openstack-ec2-api \
openstack-etcd \
openstack-glance-api \
openstack-gnocchi-api \
openstack-gnocchi-metricd \
openstack-gnocchi-statsd \
openstack-haproxy \
openstack-heat-api-cfn \
openstack-heat-api \
openstack-heat-engine \
openstack-horizon \
openstack-ironic-api \
openstack-ironic-conductor \
openstack-ironic-inspector \
openstack-ironic-neutron-agent \
openstack-ironic-pxe \
openstack-iscsid \
openstack-keepalived \
openstack-keystone \
openstack-manila-api \
openstack-manila-scheduler \
openstack-manila-share \
openstack-mariadb \
openstack-memcached \
openstack-mistral-api \
openstack-mistral-engine \
openstack-mistral-event-engine \
openstack-mistral-executor \
openstack-multipathd \
openstack-neutron-dhcp-agent \
openstack-neutron-l3-agent \
openstack-neutron-metadata-agent \
openstack-neutron-metadata-agent-ovn \
openstack-neutron-openvswitch-agent \
openstack-neutron-server \
openstack-neutron-server-ovn \
openstack-nova-api \
openstack-nova-compute \
openstack-nova-compute-ironic \
openstack-nova-conductor \
openstack-nova-libvirt \
openstack-nova-novncproxy \
openstack-nova-scheduler \
openstack-novajoin-notifier \
openstack-novajoin-server \
openstack-octavia-api \
openstack-octavia-health-manager \
openstack-octavia-housekeeping \
openstack-octavia-worker \
openstack-ovn-controller \
openstack-ovn-nb-db-server \
openstack-ovn-northd \
openstack-ovn-sb-db-server \
openstack-panko-api \
openstack-placement-api \
openstack-qdrouterd \
openstack-rabbitmq \
openstack-redis \
openstack-rsyslog \
openstack-swift-account \
openstack-swift-container \
openstack-swift-object \
openstack-swift-proxy-server \
openstack-tempest \
openstack-zaqar-wsgi \
)

ceph_images=(rhceph-4-rhel8:4)

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
