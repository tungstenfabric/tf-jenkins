#!/bin/bash -eE
set -o pipefail

systemctl disable --now apt-daily{,-upgrade}.{timer,service}
sudo apt-get update -y
sudo apt-get upgrade -y
