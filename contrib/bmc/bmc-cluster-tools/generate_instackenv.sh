#!/bin/bash

if [[ -z $1 ]]; then
    echo "$0 LAB"
    exit 1;
fi

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

rhosp_version=$1
source $my_dir/$rhosp_version.env
source $my_dir/functions.sh

echo "Generating new instackenv-$rhosp_version.json"

cd

cat <<EOF> instackenv-$rhosp_version.json
{
    "nodes":[
EOF



for vm in "${!node_4_vm[@]}"; do 
  ip_addr=${node_4_vm[$vm]};
  vbmc_port=${vbmc_port_4_vm[$vm]}
  os_name=${openstack_name_4_vm[$vm]}
  mac=$(get_mac_address $ip_addr $vm)
  generate_instackenv_block $ip_addr $vm $vbmc_port $mac $os_name
done


cat <<EOF>> instackenv-$rhosp_version.json
    ]
}
EOF


echo "New instackenv-$rhosp_version.json generated successfully"
