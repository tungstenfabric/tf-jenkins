#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

if [[ -z "$JUMPHOST" ]] ; then
  # remote worker branch
  "$my_dir/../common/create_workers.sh"
else
  "$my_dir/../../../infra/$JUMPHOST/create_workers.sh"
fi

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source "$ENV_FILE"

${my_dir}/../common/run_stage.sh openshift machines
