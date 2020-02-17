#!/bin/bash -eE
set -o pipefail

sudo apt-get update -y
sudo apt remove popularity-contest
sudo dpkg-reconfigure -plow unattended-upgrades
systemctl disable --now apt-daily{,-upgrade}.{timer,service}
sudo apt-get upgrade -y
