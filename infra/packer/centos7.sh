#!/bin/bash -eE
set -o pipefail

sudo yum update -y
sudo yum install -y bind bind-utils haproxy httpd

