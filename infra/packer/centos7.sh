#!/bin/bash -eE
sudo cat <<EOF > /etc/resolv.conf
nameserver 199.204.45.99
EOF
set -o pipefail

sudo yum update -y
