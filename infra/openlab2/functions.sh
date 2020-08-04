function remove_vm() {
    local vm_config=$1
    declare -n config=$vm_config
    virsh destroy ${config[VM_ID]} || /bin/true
    virsh undefine ${config[VM_ID]} || /bin/true
    [[ -n ${config[VM_ID]} ]] && rm -rf ${VM_IMAGES_PATH}/${config[VM_ID]}
}

function create_vm_volume() {
    local vm_config=$1
    declare -n config=$vm_config
    mkdir -p ${VM_IMAGES_PATH}/${config[VM_ID]}
    qemu-img create -b ${BASE_IMAGES_PATH}/${ENVIRONMENT_OS}.img \
                    -f qcow2 ${VM_IMAGES_PATH}/${config[VM_ID]}/${config[VM_ID]}.qcow2 ${config[VM_HDD_SIZE]}
}

function create_cloud_init_volume() {
    local vm_config=$1
    declare -n config=$vm_config
    local VM_HOSTNAME=${config[VM_HOSTNAME]}
    local VM_DOMAIM_NAME=${config[VM_DOMAIN_NAME]}
    local SSH_USER=$IMAGE_SSH_USER
    local SSH_PASSWORD=${SSH_PASSWORD:-contrail123}
    local VM_IP_ADDRESS=${config[VM_IP_ADDRESS]}
    eval "echo \"$(cat network_config_static.cfg.template)\"" > \
         ${VM_IMAGES_PATH}/${config[VM_ID]}/network_config_static.cfg
    eval "echo \"$(cat cloud_init.cfg.template)\"" > \
         ${VM_IMAGES_PATH}/${config[VM_ID]}/cloud_init.cfg
    cloud-localds -v --network-config=${VM_IMAGES_PATH}/${config[VM_ID]}/network_config_static.cfg \
                                      ${VM_IMAGES_PATH}/${config[VM_ID]}/${config[VM_ID]}-cloud-init.qcow2 \
                                      ${VM_IMAGES_PATH}/${config[VM_ID]}/cloud_init.cfg
}

function install_vm() {
    local vm_config=$1
    declare -n config=$vm_config
    virt-install --name ${config[VM_ID]} \
        --virt-type kvm \
        --memory ${config[VM_MEMORY]} \
        --vcpus ${config[VM_VCPU]} \
        --cpu host \
        --disk path=${VM_IMAGES_PATH}/${config[VM_ID]}/${config[VM_ID]}-cloud-init.qcow2,device=cdrom \
        --disk path=${VM_IMAGES_PATH}/${config[VM_ID]}/${config[VM_ID]}.qcow2,device=disk \
        --network bridge=br0,model=virtio \
        --graphics spice \
        --os-type Linux \
        --os-variant ubuntu18.04 \
        --console pty,target_type=serial \
        --noautoconsole
}

function wait_wm_up() {
    local vm_config=$1
    declare -n config=$vm_config
    timeout 300 bash -c "\
    while /bin/true ; do \
      ssh $SSH_OPTIONS $IMAGE_SSH_USER@${config[VM_IP_ADDRESS]} \
          'cat /var/log/cloud-init-output.log | grep Enjoy' && break ; \
      sleep 10 ; \
    done"
}

function spin_vm() {
    local vm_config=$1
    declare -n config=$vm_config
    remove_vm $vm_config
    create_vm_volume $vm_config
    create_cloud_init_volume $vm_config
    install_vm $vm_config
    wait_wm_up $vm_config
}
