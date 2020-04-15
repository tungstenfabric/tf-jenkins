#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$WORKSPACE/global.env"
source "$my_dir/../../../infra/${SLAVE}/definitions"
source "$my_dir/definitions"

create_env_file="$WORKSPACE/stackrc.$JOB_NAME.env"
echo "export OS_REGION_NAME=${OS_REGION_NAME}" > "$create_env_file"

IMAGE_SSH_USER=${OS_IMAGE_USERS["${ENVIRONMENT_OS^^}"]}
echo "export SSH_USER=$IMAGE_SSH_USER" >> "$create_env_file"
echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$create_env_file"

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
vexxrc="$create_env_file" ./providers/vexx/create_env.sh
