#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/../../infra/vexxhost/functions.sh"

OBJECT_NAME=jenkins-aquascan
instance_ip=$(get_instance_ip $OBJECT_NAME)
echo "export AQUASEC_HOST_IP=$instance_ip" >> ="$WORKSPACE/stackrc.$JOB_NAME.env"
