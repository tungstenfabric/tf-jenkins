#!/bin/bash -eEx
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
echo "export AWS_REGION=${AWS_REGION}" >> "$ENV_FILE"

IMAGE_VAR_NAME="IMAGE_${ENVIRONMENT_OS^^}"
IMAGE=${!IMAGE_VAR_NAME}
echo "export IMAGE=$IMAGE" >> "$ENV_FILE"

IMAGE_SSH_USER_VAR_NAME="IMAGE_${ENVIRONMENT_OS^^}_SSH_USER"
IMAGE_SSH_USER=${!IMAGE_SSH_USER_VAR_NAME}
echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$ENV_FILE"

VM_TYPE=${VM_TYPE:-'medium'}
INSTANCE_TYPE=${VM_TYPES[$VM_TYPE]}
if [[ -z "$INSTANCE_TYPE" ]]; then
    echo "ERROR: invalid VM_TYPE=$VM_TYPE"
    exit 1
fi

# Spin VM
iname=$BUILD_TAG
bdm='{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":120,"DeleteOnTermination":true}}'
instance_id=$(aws ec2 run-instances \
    --region $AWS_REGION \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$iname},{Key=PipelineBuildTag,Value=$PIPELINE_BUILD_TAG},{Key=PipelineName,Value=$PIPELINE_NAME}]" \
    --block-device-mappings "[${bdm}]" \
    --image-id $IMAGE \
    --count 1 \
    --instance-type $INSTANCE_TYPE \
    --key-name worker \
    --security-group-ids $AWS_SG \
    --subnet-id $AWS_SUBNET | \
    jq -r '.Instances[].InstanceId')
echo "export instance_id=$instance_id" >> "$ENV_FILE"
aws ec2 wait instance-running --region $AWS_REGION \
    --instance-ids $instance_id
instance_ip=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters \
    "Name=instance-state-name,Values=running" \
    "Name=instance-id,Values=$instance_id" \
    --query 'Reservations[*].Instances[*].[PrivateIpAddress]' \
    --output text)
echo "export instance_ip=$instance_ip" >> "$ENV_FILE"

timeout 300 bash -c "\
while /bin/true ; do \
  ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip 'uname -a' && break ; \
  sleep 5 ; \
done"
