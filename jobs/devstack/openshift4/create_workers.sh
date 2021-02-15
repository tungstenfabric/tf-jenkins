#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

if [[ -z "$JUMPHOST" ]] ; then
  # vexxhost/aws branch
  "$my_dir/../common/create_workers.sh"
  exit
fi

"$my_dir/../../../infra/$JUMPHOST/create_workers.sh"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source "$ENV_FILE"
$WORKSPACE/src/tungstenfabric/tf-devstack/openshift/create_env.sh
