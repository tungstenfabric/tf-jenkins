#!/bin/bash -e

if [[ -z $1 ]]; then
    echo "$0 LAB"
    exit 1;
fi

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

rhosp_version=$1
rhel_version=${rhel_version:-'rhel8.2'}
source $my_dir/$rhosp_version.env
source $my_dir/functions.sh



for vm in "${!node_4_vm[@]}"; do
  ip_addr=${node_4_vm[$vm]};
  vbmc_port=${vbmc_port_4_vm[$vm]}
  vcpu=8
  if [[ "$vm" =~ "compute" ]]; then
      vram=65536
  else
      vram=32768
  fi
  ssh $ip_addr ./create_VM.sh $vm $rhel_version $vcpu $vram
  add_vbmc $ip_addr $vm $vbmc_port
done


$my_dir/generate_instackenv.sh $rhosp_version
