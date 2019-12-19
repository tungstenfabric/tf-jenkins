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
echo "export ENV_BUILD_ID=${BUILD_ID}" > "$ENV_FILE"
echo "export OS_REGION_NAME=${OS_REGION_NAME}" >> "$ENV_FILE"

IMAGE_TEMPLATE_NAME="${OS_IMAGES["${ENVIRONMENT_OS^^}"]}"
IMAGE_NAME=$(openstack image list -c Name -f value | grep "${IMAGE_TEMPLATE_NAME}" | sort -nr | head -n 1)
IMAGE=$(openstack image show -c id -f value "$IMAGE_NAME")
echo "export IMAGE=$IMAGE" >> "$ENV_FILE"

IMAGE_SSH_USER=${OS_IMAGE_USERS["${ENVIRONMENT_OS^^}"]}
echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$ENV_FILE"

VM_TYPE=${VM_TYPE:-'medium'}
INSTANCE_TYPE=${VM_TYPES[$VM_TYPE]}
if [[ -z "$INSTANCE_TYPE" ]]; then
    echo "ERROR: invalid VM_TYPE=$VM_TYPE"
    exit 1
fi

while true; do
  [[ "$(($(nova list --tags "SLAVE=$SLAVE"  --field status | grep -c 'ID\|ACTIVE') - 1))" -lt $MAX_COUNT ]] && break
  sleep 60
done

OBJECT_NAME=$BUILD_TAG
nova boot --flavor ${INSTANCE_TYPE} \
          --security-groups ${OS_SG} \
          --key-name=worker \
          --tags "PipelineBuildTag=${PIPELINE_BUILD_TAG},SLAVE=vexxhost" \
          --nic net-name=${OS_NETWORK} \
          --block-device source=image,id=$IMAGE,dest=volume,shutdown=remove,size=120,bootindex=0 \
          --poll \
          $OBJECT_NAME

instance_id=$(openstack server show $OBJECT_NAME -c id -f value | tr -d '\n')
echo "export instance_id=$instance_id" >> "$ENV_FILE"
instance_ip=$(openstack server show $OBJECT_NAME -c addresses -f value | cut -f 2 -d '=')
echo "export instance_ip=$instance_ip" >> "$ENV_FILE"

timeout 300 bash -c "\
while /bin/true ; do \
  ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip 'uname -a' && break ; \
  sleep 10 ; \
done"
