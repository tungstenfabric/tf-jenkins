#!/bin/bash -eE
set -o pipefail

# to cleanup all workers created by current pipeline

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/functions.sh"
source "$WORKSPACE/global.env"

PIPELINE_AWS_INSTANCES=$(aws ec2 describe-instances \
                            --region "$AWS_REGION" \
                            --query 'Reservations[].Instances[].InstanceId' \
                            --filters "Name=tag:PipelineBuildTag,Values=${PIPELINE_BUILD_TAG}" \
                                      "Name=instance-state-code,Values=16" \
                            --output text)
if [[ -n "$PIPELINE_AWS_INSTANCES" ]] ; then
  echo "INFO: Instances to terminate: $PIPELINE_AWS_INSTANCES"
  terminate_instances $PIPELINE_AWS_INSTANCES
fi
