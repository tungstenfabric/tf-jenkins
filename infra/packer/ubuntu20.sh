#!/bin/bash -eE
set -o pipefail

sudo cat /etc/apt/sources.list

sudo systemctl disable --now apt-daily{,-upgrade}.{timer,service}
sudo apt update -y
sudo apt upgrade -y
sudo chsh --shell /bin/bash ubuntu
sudo cat /etc/apt/sources.list
echo "kexec-tools kexec-tools/load_kexec boolean true" | sudo debconf-set-selections
echo "kdump-tools kdump-tools/use_kdump boolean true" | sudo debconf-set-selections
sudo apt-cache search net-tools
DEBIAN_FRONTEND=noninteractive sudo apt install linux-crashdump net-tools -fy --fix-missing
