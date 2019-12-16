#!/bin/bash -eE
set -o pipefail

# to cleanup all workers created by current pipeline

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$WORKSPACE/global.env"

# TODO: check if it's locked and do not fail job

PIPELINE_AWS_INSTANCES=$(aws ec2 describe-instances \
                            --region $AWS_REGION \
                            --query 'Reservations[].Instances[].InstanceId' \
                            --filters "Name=tag:PipelineBuildTag,Values=${PIPELINE_BUILD_TAG}" \
                            --output text)
if [[ -n "$PIPELINE_AWS_INSTANCES" ]]; then
  aws ec2 terminate-instances --region $AWS_REGION --instance-ids $PIPELINE_AWS_INSTANCES
fi
