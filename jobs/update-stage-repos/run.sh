#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

if [ -z ${REPOS_TYPE} ]; then
  echo "ERROR: REPOS_TYPE is undefined or empty"
  exit 1
fi

ssh -i $REPOUPDATER_SSH_KEY $SSH_OPTIONS $REPOUPDATER_USER_NAME@tf-mirrors.tfci.progmaticlab.com "sudo /opt/mirrors/sync.sh ${REPOS_TYPE}"
