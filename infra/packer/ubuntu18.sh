#!/bin/bash -eE
set -o pipefail

sudo systemctl disable --now apt-daily{,-upgrade}.{timer,service}
sudo apt-get update -y
sudo apt-get upgrade -y
sudo chsh --shell /bin/bash ubuntu
echo "kexec-tools kexec-tools/load_kexec boolean true" | sudo debconf-set-selections
echo "kdump-tools kdump-tools/use_kdump boolean true" | sudo debconf-set-selections
DEBIAN_FRONTEND=noninteractive sudo apt install linux-crashdump -fy --fix-missing

