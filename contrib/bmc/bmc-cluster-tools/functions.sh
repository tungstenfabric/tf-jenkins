#!/bin/bash


function add_vbmc {
  ipmi_address=$1
  vm=$2
  vbmc_port=$3 	
  echo "Adding vbmc port $vbmc_port for $vm (kvm node $ipmi_address)"
  ssh $ipmi_address "vbmc add --no-daemon --port $vbmc_port --address $ipmi_address --username ADMIN --password ADMIN $vm &"
  ssh $ipmi_address vbmc start $vm
}

function del_vbmc {
  ipmi_address=$1
  vm=$2
  echo "Removing vbmc port for $vm (kvm node $ipmi_address)"
  ssh $ipmi_address vbmc delete --no-daemon $vm
}

function get_mac_address {
  ipmi_address=$1
  vm=$2
  mac_address=$(ssh $ipmi_address "virsh dumpxml $vm | grep 'mac address=' | grep -Eo '[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}'")
  echo "$mac_address"
}

function generate_instackenv_block {
  ipmi_address=$1
  vm=$2
  vbmc_port=$3
  mac_address=$4
  os_name=$5
cat <<EOF>> instackenv-$rhosp_version.json
        {
            "name":"$vm",
            "pm_type":"pxe_ipmitool",
            "pm_addr":"$ipmi_address",
            "pm_port":"$vbmc_port",
            "pm_user":"ADMIN",
            "pm_password":"ADMIN",
            "arch": "x86_64",
            "capabilities":"node:$os_name,boot_option:local",
            "mac": [
              "$mac_address"
            ]
        },
EOF

}	

