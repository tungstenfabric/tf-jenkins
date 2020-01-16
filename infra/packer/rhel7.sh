#!/bin/bash -eE
set -o pipefail

sudo subscription-manager register --username "$RHEL_USER" --password "$RHEL_PASS"
sudo yum upgrade -y
sudo subscription-manager unregister --username="$RHEL_USER"
