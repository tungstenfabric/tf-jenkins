#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

stackrc_file=${stackrc_file:-"stackrc.$JOB_NAME.env"}
stackrc_file_path=$WORKSPACE/$stackrc_file
export vexxrc="$stackrc_file_path"

for (( i=1; i<=$VM_RETRIES ; ++i )) ; do
  echo "export DEPLOY_COMPACT_AIO=$DEPLOY_COMPACT_AIO" > "$stackrc_file_path"
  echo "export ENABLE_RHEL_REGISTRATION=$ENABLE_RHEL_REGISTRATION" >> "$stackrc_file_path"
  echo "export ENABLE_NETWORK_ISOLATION=$ENABLE_NETWORK_ISOLATION" >> "$stackrc_file_path"
  echo "export OPENSTACK_CONTAINER_REGISTRY=$OPENSTACK_CONTAINER_REGISTRY" >> "$stackrc_file_path"
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
  fi

  # to prepare rhosp-provisionin.sh
  if ./src/tungstenfabric/tf-devstack/rhosp/create_env.sh ; then
    exit 0
  fi
  echo "ERROR: Instances creation is failed. Retry"
  $my_dir/remove_workers.sh || true
  sleep 60
done

echo "ERROR: Instances creation is failed at $VM_RETRIES attempts."
exit -1
