#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$WORKSPACE/global.env"

PIPELINE_AWS_INSTANCES=$(aws ec2 describe-instances \
                            --query 'Reservations[].Instances[].InstanceId' \
                            --filters "Name=tag:Pipeline,Values=${PIPELINE_BUILD_TAG}" \
                            --output text)
aws ec2 terminate-instances --region $AWS_REGION --instance-ids $PIPELINE_AWS_INSTANCES
