#!/bin/bash

source rhosp13.env
source functions.sh


for kvm in $(echo $kvm_list); do
  ssh $kvm virsh list --all
done


