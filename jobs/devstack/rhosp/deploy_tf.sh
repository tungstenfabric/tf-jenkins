#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


source "$my_dir/definitions"
# stackrc file is prepared by pipeline based on 
# previous job's artefacts
export stackrc_file=${stackrc_file:-"deps.${JOB_NAME}.${JOB_RND}.env"}
export stackrc_file_path=$WORKSPACE/$stackrc_file

function add_deployrc() {
  local file="$1"
  cat "$stackrc_file_path" >> "$file"
}
export -f add_deployrc

${my_dir}/../common/deploy_tf.sh rhosp
