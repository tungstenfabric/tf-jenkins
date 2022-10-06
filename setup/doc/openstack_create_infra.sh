#!/usr/bin/env bash

set -o errexit
set -o pipefail

KOLLA_DEBUG=${KOLLA_DEBUG:-0}

KOLLA_OPENSTACK_COMMAND=openstack

if [[ $KOLLA_DEBUG -eq 1 ]]; then
    set -o xtrace
    KOLLA_OPENSTACK_COMMAND="$KOLLA_OPENSTACK_COMMAND --debug"
fi

# This script is meant to be run once after running start for the first
# time.  This script downloads a cirros image and registers it.  Then it
# configures networking and nova quotas to allow 40 m1.small instances
# to be created.

ARCH=$(uname -m)
IMAGE_PATH=/opt/cache/files/
IMAGE_URL=https://github.com/cirros-dev/cirros/releases/download/0.5.1/
IMAGE=cirros-0.5.1-${ARCH}-disk.img
IMAGE_NAME=cirros
IMAGE_TYPE=linux

# This EXT_NET_CIDR is your public network,that you want to connect to the internet via.
ENABLE_EXT_NET=${ENABLE_EXT_NET:-1}
EXT_NET_CIDR=${EXT_NET_CIDR:-'10.87.85.0/25'}
EXT_NET_RANGE=${EXT_NET_RANGE:-'start=10.87.85.30,end=10.87.85.70'}
EXT_NET_GATEWAY=${EXT_NET_GATEWAY:-'10.87.85.126'}

# Sanitize language settings to avoid commands bailing out
# with "unsupported locale setting" errors.
unset LANG
unset LANGUAGE
LC_ALL=C
export LC_ALL
for i in curl openstack; do
    if [[ ! $(type ${i} 2>/dev/null) ]]; then
        if [ "${i}" == 'curl' ]; then
            echo "Please install ${i} before proceeding"
        else
            echo "Please install python-${i}client before proceeding"
        fi
        exit
    fi
done

# Test for credentials set
if [[ "${OS_USERNAME}" == "" ]]; then
    echo "No Keystone credentials specified. Try running source /etc/kolla/admin-openrc.sh command"
    exit
fi

# Test to ensure configure script is run only once
if $KOLLA_OPENSTACK_COMMAND router list | grep -q router1; then
    echo "This tool should only be run once per deployment."
    exit
fi


echo Configuring neutron.

$KOLLA_OPENSTACK_COMMAND router create router1

$KOLLA_OPENSTACK_COMMAND network create management
$KOLLA_OPENSTACK_COMMAND network create data
$KOLLA_OPENSTACK_COMMAND subnet create --subnet-range 10.0.0.0/19 --network management \
    --gateway 10.0.0.1 --dns-nameserver 10.84.5.101 --dns-nameserver 66.129.233.81 management
$KOLLA_OPENSTACK_COMMAND subnet create --subnet-range 10.20.0.0/16 --allocation-pool start=10.20.0.2,end=10.20.200.255 \
     --dns-nameserver 10.84.5.101 --dns-nameserver 66.129.233.81 --network data data


$KOLLA_OPENSTACK_COMMAND router add subnet router1 management

if [[ $ENABLE_EXT_NET -eq 1 ]]; then
    $KOLLA_OPENSTACK_COMMAND network create --external --provider-physical-network physnet1 \
        --provider-network-type flat public1
    $KOLLA_OPENSTACK_COMMAND subnet create --no-dhcp \
        --allocation-pool ${EXT_NET_RANGE} --network public1 \
        --subnet-range ${EXT_NET_CIDR} --gateway ${EXT_NET_GATEWAY} public1-subnet
    $KOLLA_OPENSTACK_COMMAND router set --external-gateway public1 router1
fi

# Get admin user and tenant IDs
ADMIN_PROJECT_ID=$($KOLLA_OPENSTACK_COMMAND project list | awk '/ admin / {print $2}')
ADMIN_SEC_GROUP=$($KOLLA_OPENSTACK_COMMAND security group list --project ${ADMIN_PROJECT_ID} | awk '/ default / {print $2}')


if [ ! -f ~/.ssh/plab ]; then
    echo No ssh key .ssh/plab
    exit
fi
if [ -r ~/.ssh/plab ]; then
    echo Configuring nova public key and quotas.
    ssh-keygen -y -f ~/.ssh/plab > ~/.ssh/plab.pub
    $KOLLA_OPENSTACK_COMMAND keypair create --public-key ~/.ssh/plab.pub worker
fi

openstack image create --public --file focal-server-cloudimg-amd64.img ubuntu-focal
openstack security group create allow_all
openstack security group rule create $SLAVE_REGION--ingress --protocol any --prefix '0.0.0.0/0' allow_all
$SLAVE_REGIOo
#Allow ssh and icmp in default security group
openstack security group rule create --ingress --protocol tcp --dst-port 22:22 --prefix '0.0.0.0/0' defaut
openstack security group rule create --ingress --protocol icmp --prefix '0.0.0.0/0' default

