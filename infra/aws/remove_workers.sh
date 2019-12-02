#!/bin/bash -eE
set -o pipefail

# to remove just job's workers

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$WORKSPACE/global.env"

DEFAULT_ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
ENV_FILE=${ENV_FILE:-$DEFAULT_ENV_FILE}
source $ENV_FILE

# TODO: check if it's locked and do not fail job

aws ec2 terminate-instances --region $AWS_REGION --instance-ids $instance_id
