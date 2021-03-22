#!/bin/bash -eE
set -o pipefail
set -x

id
ls -l /etc/resolv.conf
mount
sudo cat > /etc/resolv.conf <<EOF 
nameserver 199.204.45.99
EOF
sudo yum update -y
