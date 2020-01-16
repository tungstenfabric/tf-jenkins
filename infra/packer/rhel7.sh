#!/bin/bash -eE
set -o pipefail

sudo subscription-manager register --username "$RHEL_USER" --password "$RHEL_PASS"
sudo subscription-manager repos --enable rhel-7-server-rpms rhel-7-server-extras-rpms rhel-7-server-optional-rpms
sudo yum upgrade -y
sudo subscription-manager unregister --username="$RHEL_USER"
