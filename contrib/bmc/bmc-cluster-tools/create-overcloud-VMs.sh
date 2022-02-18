#!/bin/bash -e

set -o pipefail

if [[ -z $1 ]]; then
    echo "$0 LAB"
    exit 1;
fi

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

rhel_version=${rhel_version:-'rhel8.2'}
rhosp_version=${rhosp_version:-'rhosp16.1'}
source $my_dir/$1.env
source $my_dir/functions.sh

for vm in "${!node_4_vm[@]}"; do
  ip_addr=${node_4_vm[$vm]};
  vbmc_port=${vbmc_port_4_vm[$vm]}
  pool=${pool_4_vm[$vm]}
  vcpu=8
  if [[ "$vm" =~ "compute" ]]; then
      vram=65536
      diskspace='30G'
  elif [[ "$vm" =~ "ceph" ]]; then
      vcpu=2
      vram=4096
      diskspace='20G'
  else
      vram=32768
      diskspace='50G'
  fi
  ssh $ip_addr ./create_VM.sh $vm $rhel_version $pool $vcpu $vram $diskspace
  add_vbmc $ip_addr $vm $vbmc_port
done


$my_dir/generate_instackenv.sh $1

