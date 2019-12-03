#!/bin/bash -eE
set -o pipefail

# WARNING !!!!
# it creates only one machine for now !

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$WORKSPACE/global.env"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
touch "$ENV_FILE"
echo "ENV_BUILD_ID=${BUILD_ID}" > "$ENV_FILE"
echo "OS_REGION_NAME=${OS_REGION_NAME}" >> "$ENV_FILE"

IMAGE_TEMPLATE_NAME=${OS_IMAGES["${ENVIRONMENT_OS^^}"]}
IMAGE=$(openstack image list --private -c Name --format value | grep ${IMAGE_TEMPLATE_NAME} | sort -nr | head -n 1)
echo "IMAGE=$IMAGE" >> "$ENV_FILE"

echo "IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$ENV_FILE"

VM_TYPE=${VM_TYPE:-'medium'}
INSTANCE_TYPE=${VM_TYPES[$VM_TYPE]}
if [[ -z "$INSTANCE_TYPE" ]]; then
    echo "ERROR: invalid VM_TYPE=$VM_TYPE"
    exit 1
fi

OBJECT_NAME=$BUILD_TAG
VOLUME_ID=$(openstack volume create -c id --format value  \
    --size 60 \
    --image ${IMAGE} \
    --property Pipeline=${PIPELINE_BUILD_TAG} \
    --bootable \
    ${OBJECT_NAME} )
echo "volume_id=$VOLUME_ID" >> "$ENV_FILE"

for ((i=0; i<10; ++i)); do
  sleep 5
  volume_status=$(openstack volume list -c Status -f value --name ${OBJECT_NAME})
  if [[ "$volume_status" == 'available' ]]; then
    break
  fi
done

INSTANCE_ID=$(openstack server create -c id -f value \
    --volume ${VOLUME_ID} \
    --flavor ${INSTANCE_TYPE} \
    --security-group ${OS_SG} \
    --key-name=worker \
    --property Pipeline=${PIPELINE_BUILD_TAG} \
    --network=${OS_NETWORK} \
    --availability-zone=${OS_AZ} \
    --wait \
    $OBJECT_NAME)
echo "instance_id=$INSTANCE_ID" >> "$ENV_FILE"

INSTANCE_IP=$(openstack server show $OBJECT_NAME -c addresses -f value | cut -f2 -d=)
echo "instance_ip=$INSTANCE_IP" >> "$ENV_FILE"
