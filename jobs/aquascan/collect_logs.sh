#!/bin/bash

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS $LOGS_HOST_USERNAME@$LOGS_HOST "mkdir -p $FULL_LOGS_PATH"
find ${WORKSPACE} -maxdepth 1 -name \*.xlsx -printf "%f\n" | rsync --remove-source-files -ave "ssh -i ${LOGS_HOST_SSH_KEY} ${SSH_OPTIONS}" --files-from=- ${WORKSPACE} ${LOGS_HOST_USERNAME}@${LOGS_HOST}:${FULL_LOGS_PATH}
