#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export DEBIAN_FRONTEND=noninteractive
sudo apt-get install maas-cli -y

maas login $PROFILE $MAAS_ENDPOINT - <<< $(echo $MAAS_API_KEY)
machines=$(maas $PROFILE machines read | jq -r '.[] | .system_id')

for machine in $machines; do
    maas $PROFILE machine release $machine
done

if [ -n "$1" ]; then
  echo "export MAAS_ENDPOINT=\"$MAAS_ENDPOINT\"" >> "$1"
  echo "export MAAS_API_KEY=\"$MAAS_API_KEY\"" >> "$1"
  echo "export VIRTUAL_IPS=\"$VIRTUAL_IPS\"" >> "$1"
fi

echo "INFO: MAAS is ready "
echo "INFO: MAAS web ui $MAAS_ENDPOINT"
echo "Set variables to use with juju deployment:"
echo "export MAAS_ENDPOINT=\"$MAAS_ENDPOINT\""
echo "export MAAS_API_KEY=\"$MAAS_API_KEY\""
echo "export VIRTUAL_IPS=\"$VIRTUAL_IPS\""
