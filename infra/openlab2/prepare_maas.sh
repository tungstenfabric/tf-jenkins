#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export DEBIAN_FRONTEND=noninteractive
sudo apt-get install maas-cli -y

maas login $PROFILE $MAAS_ENDPOINT - <<< $(echo $MAAS_API_KEY)
maas $PROFILE nodes read