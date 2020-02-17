#!/bin/bash -eE
set -o pipefail

sudo apt-get update -y
systemctl disable --now apt-daily{,-upgrade}.{timer,service}
sudo apt-get upgrade -y
