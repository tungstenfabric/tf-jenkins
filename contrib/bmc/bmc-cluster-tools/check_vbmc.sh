#!/bin/bash


my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/rhosp16.1-ha.env
source functions.sh


for kvm in $(echo $kvm_list); do
  ssh $kvm vbmc list
done


