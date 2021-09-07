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

output_file="instackenv-${rhosp_version}.json"

echo "Generating new $output_file"

cd

cat <<EOF> $output_file
{
    "nodes":[
EOF



for vm in "${!node_4_vm[@]}"; do
  ip_addr=${node_4_vm[$vm]};
  vbmc_port=${vbmc_port_4_vm[$vm]}
  os_name=${openstack_name_4_vm[$vm]}
  mac=$(get_mac_address $ip_addr $vm)
  generate_instackenv_block $output_file $ip_addr $vm $vbmc_port $mac $os_name
done

#Removing the latest comma
truncate -s-2 $output_file
cat <<EOF>> $output_file

EOF

cat <<EOF>> $output_file
    ]
}
EOF


echo "New $output_file generated successfully"
