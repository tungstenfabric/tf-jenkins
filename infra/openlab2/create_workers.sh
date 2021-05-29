#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ssh_cmd="ssh -F $my_dir/ssh_config"
rsync -a -e "$ssh_cmd" $my_dir/* openlab2:./
$ssh_cmd openlab2 ./run_create_worker.sh

ssh_config="$(cat $my_dir/ssh_config | base64 -w 0)"
ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
touch "$ENV_FILE"
echo "export PROVIDER=$PROVIDER" >> "$ENV_FILE"
echo "export ENVIRONMENT_OS=$ENVIRONMENT_OS" >> "$ENV_FILE"
echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$ENV_FILE"
echo "export instance_ip=${worker[VM_IP_ADDRESS]}" >> "$ENV_FILE"
echo "echo $ssh_config | base64 --decode > \$WORKSPACE/ssh_config " >> $ENV_FILE
echo "export SSH_EXTRA_OPTIONS=\"-F \$WORKSPACE/ssh_config -J openlab2\"" >> "$ENV_FILE"
