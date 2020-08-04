#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

export DEBIAN_FRONTEND=noninteractive
sudo apt-get install maas-cli jq -y

maas login $MAAS_PROFILE $MAAS_ENDPOINT - <<< $(echo $MAAS_API_KEY)
machines=$(maas $MAAS_PROFILE machines read | jq -r '.[] | .system_id')

for machine in $machines; do
    maas $MAAS_PROFILE machine release $machine
done

for ((i=0; i<10; ++i)); do
  MACHINES_STATUS=`maas $PROFILE machines read | jq -r '.[].status_name'`
  MACHINES_COUNT=`echo "$MACHINES_STATUS" | wc -l`
  if echo "$MACHINES_STATUS" | grep -q "Ready"; then
    READY_COUNT=`echo "$MACHINES_STATUS" | grep -c "Ready"`
    if [[ $READY_COUNT == $MACHINES_COUNT ]]; then
      break
    fi
  fi
  sleep 10
done

if [[ $READY_COUNT != $MACHINES_COUNT ]]; then
  echo "ERROR: Machines not ready"
  exit 1
fi

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
