#!/bin/bash -eE
set -o pipefail

sudo yum update -y

sudo sed -i "s/^.*UseDNS.*/UseDNS no/" /etc/ssh/sshd_config
