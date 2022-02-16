#!/bin/bash

source rhosp16.1-ha.env
source functions.sh


for kvm in $(echo $kvm_list); do
  ssh $kvm virsh list --all
done


