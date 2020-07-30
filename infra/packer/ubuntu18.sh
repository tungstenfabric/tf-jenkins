#!/bin/bash -eE
set -o pipefail

sudo systemctl disable --now apt-daily{,-upgrade}.{timer,service}
sudo apt-get update -y
sudo apt-get upgrade -y
