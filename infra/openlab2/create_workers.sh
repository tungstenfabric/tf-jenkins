#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ssh_cmd="ssh -i $OPENLAB2_SSH_KEY $SSH_OPTIONS -p 30002"
rsync -a -e "$ssh_cmd" $my_dir/*  jenkins@openlab.tf-jenkins.progmaticlab.com:./

eval $ssh_cmd -p 30002 jenkins@openlab.tf-jenkins.progmaticlab.com ./run_create_worker.sh
ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
touch "$ENV_FILE"
echo "export ENVIRONMENT_OS=$ENVIRONMENT_OS" >> "$ENV_FILE"
echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$ENV_FILE"
echo "export instance_ip=${worker[VM_IP_ADDRESS]}" >> "$ENV_FILE"
echo "export SSH_EXTRA_OPTIONS=\"-o ProxyCommand=\\\"ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -W %h:%p -i \$OPENLAB2_SSH_KEY -l jenkins -p 30002 openlab.tf-jenkins.progmaticlab.com\\\"\"" >> "$ENV_FILE"
