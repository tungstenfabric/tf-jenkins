#!/bin/bash

function delete_network_dhcp() {
  local network_name="$1"
  virsh net-destroy $network_name 2> /dev/null || true
  virsh net-undefine $network_name 2> /dev/null || true
}

function create_network_dhcp() {
  local network_name=$1
  local addr=$2
  local brname=$3
  local dhcp=${4:-'yes'}
  local forward=${5:-'nat'}
  local fxml=$(build_network_xml_dhcp $network_name $addr $brname $dhcp $forward)
  virsh net-define $fxml
  rm -f $fxml
  virsh net-autostart $network_name
  virsh net-start $network_name
}

function build_network_xml_dhcp() {
  local nname=$1
  local network=$2
  local brname=$3
  local dhcp=$4
  local forward=$5
  local fname=`mktemp`
  local net_base_ip=$(echo "$network" | cut -d '.' -f 1,2,3)
  local nic_ip_last=$(echo "$network" | cut -d '.' -f 4)
  if [[ -z "$nic_ip_last" || $"nic_ip_last" == '0' ]]; then
    nic_ip_last=1
  fi
  local nic_ip="${net_base_ip}.${nic_ip_last}"
  local dhcp_start="${net_base_ip}.100"
  local dhcp_end="${net_base_ip}.200"
  cat <<EOF > $fname
<network>
  <name>$nname</name>
  <bridge name="$brname"/>
EOF
  if  [[ "$forward" != "no_forward" ]] ; then
  cat <<EOF >> $fname
  <forward mode="$forward"/>
EOF
  fi
  cat <<EOF >> $fname
  <domain name='localdomain' localOnly='yes'/>
  <ip address="$nic_ip" netmask="255.255.255.0">
EOF
  if  [[ "$dhcp" == "yes" ]] ; then
  cat <<EOF >> $fname
    <dhcp>
      <range start="$dhcp_start" end="$dhcp_end"/>
    </dhcp>
EOF
  fi
  cat <<EOF >> $fname
  </ip>
</network>
EOF

  echo $fname
}

function create_pool() {
  local poolname="$1"
  local path="/var/lib/libvirt/$poolname"
  if ! sudo virsh pool-info $poolname &> /dev/null ; then
    sudo virsh pool-define-as $poolname dir - - - - "$path"
    sudo virsh pool-build $poolname
    sudo virsh pool-start $poolname
    sudo virsh pool-autostart $poolname
  fi
}

function get_pool_path() {
  local poolname=$1
  sudo virsh pool-info $poolname &>/dev/null || return
  sudo virsh pool-dumpxml $poolname | sed -n '/path/{s/.*<path>\(.*\)<\/path>.*/\1/;p}'
}

function create_volume() {
  local name=$1
  local poolname=$2
  local vm_disk_size=$3
  delete_volume $name.qcow2 $poolname
  local pool_path=$(get_pool_path $poolname)
  sudo qemu-img create -f qcow2 -o preallocation=metadata $pool_path/$name.qcow2 $vm_disk_size 1>/dev/null
  echo $pool_path/$name.qcow2
}

function create_volume_from() {
  local vol=$1
  local pool=$2
  local src_vol=$3
  local src_pool=$4
  local vol_file=`mktemp`
  cat <<EOF > $vol_file
<volume type='file'>
  <name>$vol</name>
  <target>
    <format type='qcow2'/>
  </target>
</volume>
EOF
  sudo virsh vol-create-from --pool $pool --file $vol_file --vol $src_vol --inputpool $src_pool 1>/dev/null
  local pool_path=$(get_pool_path $pool)
  echo $pool_path/$vol
}

function create_new_volume() {
  local vol=$1
  local pool=$2
  local size_gb=$3
  local vol_file=`mktemp`
  cat <<EOF > $vol_file
<volume type='file'>
  <name>$vol</name>
  <capacity unit='gb'>$size_gb</capacity>
  <target>
    <format type='qcow2'/>
    <permissions>
      <mode>0644</mode>
    </permissions>
  </target>
</volume>
EOF
  sudo virsh vol-create --pool $pool --file $vol_file 1>/dev/null
  local pool_path=$(get_pool_path $pool)
  echo $pool_path/$vol
}

function assert_env_exists() {
  local name=$1
  if sudo virsh list --all | grep -q "$name" ; then
    echo 'ERROR: environment present. please clean up first'
    sudo virsh list --all | grep "$name"
    exit 1
  fi
}

function create_vm() {
  local vm_name=$1
  local vcpus=$2
  local mem=$3
  local image=$4
  local mac_octet=$5

  local vol_name="$vm_name.qcow2"
  delete_volume $vol_name $POOL_NAME
  local vol_path=$(create_volume_from $vol_name $POOL_NAME $image $BASE_IMAGE_POOL)

  local opt_disks=''
  local index=0
  for ((; index<${#ADDITIONAL_DISKS[*]}; ++index)); do
    local opt_vol_name="$vm_name-$index.qcow2"
    delete_volume $opt_vol_name $POOL_NAME
    local opt_vol_path=$(create_new_volume $opt_vol_name $POOL_NAME $ADDITIONAL_DISK_SIZE)
    opt_disks+=" $opt_vol_path $ADDITIONAL_DISK_SIZE"
  done

  local net="$KVM_NETWORK/52:54:00:00:10:$mac_octet"
  #for ((j=1; j<NET_COUNT; ++j)); do
  #  net="$net,${KVM_NETWORK}_$j/52:54:00:00:$((10+j)):$mac_octet"
  #done
  define_machine $vm_name $vcpus $mem $OS_VARIANT $net $vol_path $opt_disks
  start_vm $vm_name
}

function attach_opt_vols() {
  local letters=(b c d e f g h)
  local ip=$1
  local index=0
  for ((; index<${#ADDITIONAL_DISKS[*]}; ++index)); do
    # 98 - char 'b'
    local letter=${letters[index]}
    local path=${ADDITIONAL_DISKS[index]}
    cat <<EOF | ssh $SSH_OPTS root@${ip}
(echo o; echo n; echo p; echo 1; echo ; echo ; echo w) | fdisk /dev/vd${letter}
mkfs.ext4 /dev/vd${letter}1
mkdir -p ${path}
echo '/dev/vd${letter}1  ${path}  auto  defaults,auto  0  0' >> /etc/fstab
mount ${path}
EOF
  done
}

function define_machine() {
  # parameter net could be: netname1,netname2
  # or netname1/mac1,netname2/mac
  local name=$1
  local vcpus=$2
  local mem=$3
  local os=$4
  local net=$5
  local disk_path=$6
  shift 6
  NET_DRIVER=${NET_DRIVER:-'virtio'}
  local disk_opts="path=${disk_path},device=disk,cache=writeback,bus=virtio,format=qcow2"
  local net_opts=''
  local i=''
  for i in $(echo $net | tr ',' ' ') ; do
    local nname=$(echo $i | cut -d '/' -f 1)
    local mac=$(echo $i | cut -s -d '/' -f 2)
    net_opts+=" --network network=${nname},model=$NET_DRIVER"
    if [[ -n "$mac" ]] ; then
      net_opts+=",mac=${mac}"
    fi
  done
  local more_disks=''
  while (($# > 1)) ; do
    local path=$1 ; shift
    local size=${1:-60} ; shift
    more_disks+=" --disk path=${path},device=disk,cache=writeback,bus=virtio,format=qcow2,size=${size}"
  done
  sudo rm -f /tmp/oc-$name.xml
  sudo virt-install --name $name \
    --ram $mem \
    --memorybacking hugepages=on \
    --vcpus $vcpus \
    --cpu host \
    --os-variant $os \
    --disk $disk_opts \
    $more_disks \
    $net_opts \
    --boot hd \
    --noautoconsole \
    --graphics vnc,listen=0.0.0.0 \
    --dry-run --print-xml > /tmp/oc-$name.xml
  sudo virsh define --file /tmp/oc-$name.xml
}

function start_vm() {
  local name=$1
  sudo virsh start $name --force-boot
}

function delete_domain() {
  local name=$1
  if sudo virsh dominfo $name 2>/dev/null ; then
    sudo virsh destroy $name || true
    sleep 2
    sudo virsh undefine $name || true
  fi
  delete_vbmc $name
}

function delete_volume() {
  local volname=$1
  local poolname=$2
  local pool_path=$(get_pool_path $poolname)
  sudo virsh vol-delete $volname --pool $poolname 2>/dev/null || rm -f $pool_path/$volname 2>/dev/null
}

function wait_dhcp() {
  local net=$1
  local count=${2:-1}
  local host=${3:-''}
  local max_iter=${4:-20}
  local iter=0
  local filter="ipv4"
  if [[ -n "$host" ]] ; then
    filter+=".*${host}"
  fi
  while true ; do
    local ips=( `sudo virsh net-dhcp-leases $net | sed 1,2d | grep "$filter" | awk '{print($5)}' | cut -d '/' -f 1` )
    if (( ${#ips[@]} == count )) ; then
      break
    fi
    if (( iter >= max_iter )) ; then
      echo "ERROR: Failed to wait for $count ip addresses allocation via dhcp" >&2
      exit 1
    fi
    echo "INFO: Waiting for $count dhcp address requested... $iter" >&2
    sleep 30
    ((++iter))
  done
}

function get_ip_by_mac() {
  local net=$1
  local filter=$2
  sudo virsh net-dhcp-leases $net | sed 1,2d | grep "$filter" | awk '{print($5)}' | cut -d '/' -f 1
}

function wait_ssh() {
  local addr=$1
  local ssh_key=${2:-''}
  local max_iter=${3:-20}
  local iter=0
  ssh_key_opt=''
  if [[ -n "$ssh_key" ]] ; then
    ssh_key_opt=" -i $ssh_key"
  fi
  truncate -s 0 ./tmp_file
  while ! scp $ssh_key_opt $SSH_OPTS -B ./tmp_file root@${addr}:/tmp/tmp_file ; do
    if (( iter >= max_iter )) ; then
      echo "ERROR: Could not connect to VM $addr"
      return 1
    fi
    echo "INFO: Waiting for VM $addr..."
    sleep 30
    ((++iter))
  done
}
