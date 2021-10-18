#!/bin/bash

if [[ -z $1 ]]; then
    echo "$0 LAB"
    exit 1;
fi

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/$1.env
source functions.sh

virt-clone --original ${undercloud_vm}-original --name ${undercloud_vm} --auto-clone
virsh start $undercloud_vm

$my_dir/create-overcloud-VMs.sh $1

