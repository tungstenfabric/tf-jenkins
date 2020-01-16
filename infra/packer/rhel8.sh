#!/bin/bash -eE
set -o pipefail

sudo subscription-manager register --username "$RHEL_USER" --password "$RHEL_PASSWORD"
sudo subscription-manager attach --pool $RHEL_POOL_ID
sudo subscription-manager repos --enable=rhel-8-server-rpms \
                                --enable=rhel-8-server-extras-rpms \
                                --enable=rhel-8-server-optional-rpms
sudo yum update -y
sudo subscription-manager unregister
