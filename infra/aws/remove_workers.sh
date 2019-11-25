#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

for f in $WORKSPACE/stackrc.deploy-platform-*.env; do
  source $f
  aws ec2 terminate-instances --region $AWS_REGION --instance-ids $instance_id
done
