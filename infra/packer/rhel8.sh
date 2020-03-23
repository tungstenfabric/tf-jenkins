#!/bin/bash -eE
set -o pipefail

sudo subscription-manager register --username "$RHEL_USER" --password "$RHEL_PASSWORD"
sudo subscription-manager attach --pool $RHEL_POOL_ID
sudo subscription-manager repos --enable=rhel-8-for-x86_64-baseos-rpms \
                                --enable=rhel-8-for-x86_64-appstream-rpms
sudo yum update -y
sudo subscription-manager unregister
sudo sed -i '/192\.168\.122\.1/d' /etc/resolv.conf
