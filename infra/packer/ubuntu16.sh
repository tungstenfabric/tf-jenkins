#!/bin/bash -eE
set -o pipefail

sudo apt-get update -y
sudo apt-get remove unattended-upgrades -y
sudo apt-get upgrade -y
