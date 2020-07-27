#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

stackrc_file=${stackrc_file:-"stackrc.$JOB_NAME.env"}
stackrc_file_path=$WORKSPACE/$stackrc_file

echo "export DEPLOY_COMPACT_AIO=$DEPLOY_COMPACT_AIO" > "$stackrc_file_path"
echo "export ENABLE_RHEL_REGISTRATION=$ENABLE_RHEL_REGISTRATION" >> "$stackrc_file_path"
echo "export ENABLE_NETWORK_ISOLATION=$ENABLE_NETWORK_ISOLATION" >> "$stackrc_file_path"
echo "export OPENSTACK_CONTAINER_REGISTRY=$OPENSTACK_CONTAINER_REGISTRY" >> "$stackrc_file_path"
echo "export CONTRAIL_CONTAINER_SRC_TAG=$CONTRAIL_CONTAINER_SRC_TAG" >> "$stackrc_file_path"
echo "export PROVIDER=$PROVIDER" >> "$stackrc_file_path"

if [[ -n "$CLOUD" ]]; then
    source "$my_dir/../../../infra/${CLOUD}/definitions"

    $my_dir/../../../infra/${CLOUD}/create_workers.sh
else
    source "$my_dir/../../../infra/${SLAVE}/definitions"

    echo "export OS_REGION_NAME=${OS_REGION_NAME}" >> "$stackrc_file_path"
    IMAGE_SSH_USER=${OS_IMAGE_USERS["${ENVIRONMENT_OS^^}"]}
    echo "export SSH_USER=$IMAGE_SSH_USER" >> "$stackrc_file_path"
    echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$stackrc_file_path"

    # wait for free resource
    while true; do
      [[ "$(($(nova list --tags "SLAVE=$SLAVE"  --field status | grep -c 'ID\|ACTIVE') - 1))" -lt "$MAX_COUNT_VM" ]] && break
      sleep 60
    done

    while true; do
      [[ "$(nova quota-show --detail | grep cores | sed 's/}.*/}/'| tr -d "}" | awk '{print $NF}')" -lt "$MAX_COUNT_VCPU" ]] && break
      sleep 60
    done


    cd src/tungstenfabric/tf-devstack/rhosp
    vexxrc="$stackrc_file_path" ./providers/vexx/create_env.sh
fi
