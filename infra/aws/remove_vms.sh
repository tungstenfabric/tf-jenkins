#!/bin/bash -e

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

source ENV_FILE="$WORKSPACE/stackrc"
aws ec2 terminate-instances --region $AWS_REGION --instance-ids $instance_id
