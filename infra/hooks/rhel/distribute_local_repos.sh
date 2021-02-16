#!/bin/bash 

cd
source rhosp-environment.sh

SSH_USER=${SSH_USER:-'cloud-user'}
nodes_list="$overcloud_cont_prov_ip, $overcloud_compute_prov_ip, $overcloud_ctrlcont_prov_ip, $ipa_prov_ip"
nodes=$(echo $nodes_list | sed -e s/,,//g | tr "," " ")
echo "INFO: distribute_local_repos.sh - nodes: $nodes"
IFS=' '
read -a strarr <<< "$nodes"

for node in "${strarr[@]}"; do
    echo "INFO: Copy file local.repo to the node $node"
    scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ./local.repo ${SSH_USER}@${node}:
    ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${SSH_USER}@${node} 'sudo rm -f /etc/yum.repos.d/*'
    ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${SSH_USER}@${node} 'sudo cp -f ./local.repo /etc/yum.repos.d/local.repo'
done
