#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

if [ -z ${REPOS_TYPE} ]; then
  echo "ERROR: REPOS_TYPE is undefined or empty"
  exit 1
fi

cat <<EOF | ssh -i $REPOUPDATER_SSH_KEY $SSH_OPTIONS $REPOUPDATER_USER_NAME@tf-mirrors.$CI_DOMAIN
export CI_DOMAIN=$CI_DOMAIN
sudo -E /opt/mirrors/publish_stage.sh ${REPOS_TYPE}
EOF
