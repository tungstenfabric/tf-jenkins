#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/../../../infra/${JUMPHOST}/definitions"

export stackrc_file=${stackrc_file:-"stackrc.$JOB_NAME.env"}
stackrc_file_path=$WORKSPACE/$stackrc_file

# TAG_SUFFIX is defined in vars.deploy-platform-rhosp13.23584.env
# but CONTRAIL_CONTAINER_TAG is defined in global.env w/o suffix
# So, global is sourced before vars and CONTRAIL_CONTAINER_TAG is w/o suffix here
if [ -n "$TAG_SUFFIX" ] ; then
  export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
  export CONTRAIL_DEPLOYER_CONTAINER_TAG="$CONTRAIL_DEPLOYER_CONTAINER_TAG$TAG_SUFFIX"
  export CONTRAIL_CONTAINER_TAG_ORIGINAL="$CONTRAIL_CONTAINER_TAG_ORIGINAL$TAG_SUFFIX"
  export CONTRAIL_DEPLOYER_CONTAINER_TAG_ORIGINAL="$CONTRAIL_DEPLOYER_CONTAINER_TAG_ORIGINAL$TAG_SUFFIX"
fi

for (( i=1; i<=$VM_RETRIES ; ++i )) ; do
  echo "export DEPLOY_COMPACT_AIO=$DEPLOY_COMPACT_AIO" > "$stackrc_file_path"
  echo "export ENABLE_RHEL_REGISTRATION=$ENABLE_RHEL_REGISTRATION" >> "$stackrc_file_path"
  if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then
    cat << EOF >> "$stackrc_file_path"
state="\$(set +o)"
[[ "\$-" =~ e ]] && state+="; set -e"
set +x
export RHEL_USER="$RHEL_USER"
export RHEL_PASSWORD="$RHEL_PASSWORD"
export RHEL_POOL_ID="$RHEL_POOL_ID"
eval "\$state"
EOF
  fi
  echo "export ENABLE_NETWORK_ISOLATION=$ENABLE_NETWORK_ISOLATION" >> "$stackrc_file_path"
  echo "export OPENSTACK_CONTAINER_REGISTRY=$OPENSTACK_CONTAINER_REGISTRY" >> "$stackrc_file_path"
  echo "export OPENSTACK_CONTAINER_TAG=$OPENSTACK_CONTAINER_TAG" >> "$stackrc_file_path"
  echo "export PROVIDER=$PROVIDER" >> "$stackrc_file_path"
  if [[ "${SSL_ENABLE,,}" == 'true' ]] ; then 
    echo "export ENABLE_TLS='ipa'" >> "$stackrc_file_path"
  fi

  if [[ "$PROVIDER" == 'bmc' ]]; then
    # openlab1
    $my_dir/../../../infra/${JUMPHOST}/create_workers.sh
  else
    # vexxhost
    echo "export OS_REGION_NAME=${OS_REGION_NAME}" >> "$stackrc_file_path"
    IMAGE_SSH_USER=${OS_IMAGE_USERS["${ENVIRONMENT_OS^^}"]}
    echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$stackrc_file_path"

    # initial values for undercloud (v2-standard-4)
    total_nodes_count=1
    total_vcpu_count=4
    if [ -z "$NODES" ] ; then
      # default aio (v2-standard-8)
      total_nodes_count=$(( total_nodes_count + 1 ))
      total_vcpu_count=$(( total_vcpu_count + 8 ))
    fi
    for nodes in ${NODES//,/ }; do
      if [[ "$(echo "$nodes" | tr -cd ':' | wc -m)" != 2 ]]; then
        echo "ERROR: inappropriate input \"$nodes\" in \"$NODES\""
        exit 1
      fi
      node_name=$(echo $nodes | cut -d ':' -f1)
      node_flavor=${VM_TYPES[$(echo $nodes | cut -d ':' -f2)]}
      node_count=$(echo $nodes | cut -d ':' -f3)
      echo "export $node_name=\"$node_flavor:$node_count\"" >> "$stackrc_file_path"
      for (( i=1; i<=5 ; ++i )) ; do
        if node_vcpu=$(openstack flavor show $node_flavor | awk '/vcpus/{print $4}') ; then
          break
        fi
        sleep 10
      done
      total_nodes_count=$(( total_nodes_count + node_count ))
      total_vcpu_count=$(( total_vcpu_count + node_count * node_vcpu ))
    done
    if [[ "${SSL_ENABLE,,}" == 'true' ]] ; then
      # ipa (v2-highcpu-4)
      total_nodes_count=$(( total_nodes_count + 1 ))
      total_vcpu_count=$(( total_vcpu_count + 4 ))
    fi
    echo "INFO: wait for enough resources for total_nodes_count=$total_nodes_count"
    # wait for free resource
    while true; do
      [[ "$(($(nova list --tags "SLAVE=$SLAVE"  --field status | grep -c 'ID\|ACTIVE') + total_nodes_count ))" -lt "$MAX_COUNT_VM" ]] && break
      sleep 60
    done
    echo "INFO: wait for enough resources for total_vcpu_count=$total_vcpu_count"
    while true; do
      [[ "$(($(nova quota-show --detail | grep cores | sed 's/}.*/}/'| tr -d "}" | awk '{print $NF}') + total_vcpu_count ))" -lt "$MAX_COUNT_VCPU" ]] && break
      sleep 60
    done
  fi
  echo "export SSH_USER=$IMAGE_SSH_USER" >> "$stackrc_file_path"

  # to prepare rhosp-environment.sh
  source $stackrc_file_path
  export vexxrc="$stackrc_file_path"
  if ./src/tungstenfabric/tf-devstack/rhosp/create_env.sh ; then
    echo "INFO: Running up hooks"
    if [[ -e $my_dir/../../../infra/hooks/rhel/up.sh ]] ; then
       ${my_dir}/../../../infra/hooks/rhel/up.sh
    fi
    exit 0
  fi
  echo "ERROR: Instances creation is failed. Retry"
  $my_dir/remove_workers.sh || true
  sleep 60
done

echo "ERROR: Instances creation is failed at $VM_RETRIES attempts."
exit -1
