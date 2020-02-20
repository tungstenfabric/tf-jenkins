#!/bin/bash -eE
set -o pipefail

# WARNING !!!!
# it creates only one machine for now !

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/functions.sh"
source "$WORKSPACE/global.env"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
touch "$ENV_FILE"
echo "export OS_REGION_NAME=${OS_REGION_NAME}" > "$ENV_FILE"

IMAGE_TEMPLATE_NAME="${OS_IMAGES["${ENVIRONMENT_OS^^}"]}"
IMAGE_NAME=$(openstack image list --status active -c Name -f value | grep "${IMAGE_TEMPLATE_NAME}" | sort -nr | head -n 1)
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
echo "INFO: VM_TYPE=$VM_TYPE"

# wait for free resource
while true; do
  [[ "$(($(nova list --tags "SLAVE=$SLAVE"  --field status | grep -c 'ID\|ACTIVE') - 1))" -lt "$MAX_COUNT_VM" ]] && break
  echo "INFO: waiting for free worker"
  sleep 60
done
#ToDo: Use the number of flavor vcpu
while true; do
  [[ "$(nova quota-show --detail | grep cores | sed 's/}.*/}/'| tr -d "}" | awk '{print $NF}')" -lt "$MAX_COUNT_VCPU" ]] && break
  echo "INFO: waiting for CPU resources"
  sleep 60
done

echo "INFO: run nova boot..."
# run machine
OBJECT_NAME=$BUILD_TAG
nova boot --flavor ${INSTANCE_TYPE} \
          --security-groups ${OS_SG} \
          --key-name=worker \
          --tags "PipelineBuildTag=${PIPELINE_BUILD_TAG},SLAVE=vexxhost,DOWN=${OS_IMAGES_DOWN["${ENVIRONMENT_OS^^}"]}" \
          --nic net-name=${OS_NETWORK} \
          --block-device source=image,id=$IMAGE,dest=volume,shutdown=remove,size=120,bootindex=0 \
          --poll \
          $OBJECT_NAME

instance_id=$(openstack server show $OBJECT_NAME -c id -f value | tr -d '\n')
echo "export instance_id=$instance_id" >> "$ENV_FILE"
instance_ip=$(get_instance_ip $OBJECT_NAME)
echo "export instance_ip=$instance_ip" >> "$ENV_FILE"

timeout 300 bash -c "\
while /bin/true ; do \
  ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip 'uname -a' && break ; \
  sleep 10 ; \
done"

image_up_script=${OS_IMAGES_UP["${ENVIRONMENT_OS^^}"]}
if [[ -n "$image_up_script" && -e ${my_dir}/../hooks/${image_up_script}/up.sh ]] ; then
  ${my_dir}/../hooks/${image_up_script}/up.sh
fi
