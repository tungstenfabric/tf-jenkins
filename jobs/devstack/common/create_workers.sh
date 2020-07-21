#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"

if [[ -z "$NODES" ]]; then
    echo "NODES declaration error: \"$NODES\""
    echo "creating one controller"

    export WORKER_NAME_PREFIX="cn"
    export VM_TYPE="$VM_TYPE"
    export NODES_COUNT="1"
    if ! "$my_dir/../../../infra/${SLAVE}/create_workers.sh" ; then
        echo "ERROR: Instances were not created. Exit"
        exit 1
    fi
    exit 0
fi

ssh-keygen -t rsa -N "" -f new_key
pub_key=$(cat new_key.pub)
env_export=""; instance_ip=""; ssh_user=""

for nodes in $( echo $NODES | tr ',' ' ' ) ; do
    if [[ "$(echo "$nodes" | tr -cd ':' | wc -m)" != 2 ]]; then
        echo "ERROR: inappropriate input \"$nodes\" in \"$NODES\""
        exit 1
    fi

    export WORKER_NAME_PREFIX="$(echo ${nodes,,} | cut -d ':' -f1 | tr '_' ' ' |
        awk '{for(i=1;i<=NF;i++) $i=substr($i,1,1)}1' | tr -d ' ')"
    export VM_TYPE="$(echo $nodes | cut -d ':' -f2)"
    export NODES_COUNT="$(echo $nodes | cut -d ':' -f3)"

    if [[ -z "$WORKER_NAME_PREFIX" || -z "$VM_TYPE" || -z "$NODES_COUNT" ]]; then
        echo "ERROR: one of parameters is empty in NODES=$NODES [$nodes]"
        exit 1
    elif ! "$my_dir/../../../infra/${SLAVE}/create_workers.sh" ; then
        echo "ERROR: Instances were not created. Exit"
        exit 1
    fi

    INSTANCE_IDS+="$(cat $ENV_FILE | grep INSTANCE_IDS | cut -d'=' -f2)"
    NEW_NODES="$(cat $ENV_FILE | grep INSTANCE_IPS | cut -d'=' -f2)"
    env_export+="export $(echo $nodes | cut -d ':' -f1)=\"$NEW_NODES\"\n"
    [[ -n $ssh_user ]] || ssh_user="$(cat $ENV_FILE | grep IMAGE_SSH_USER | cut -d'=' -f2)"
    [[ -n $instance_ip ]] || instance_ip="$(echo $NEW_NODES | cut -d',' -f1)"
    sed -i '/INSTANCE_IDS=/d' "$ENV_FILE"
    sed -i '/INSTANCE_IPS=/d' "$ENV_FILE"

    for ip in $( echo $NEW_NODES | tr ',' ' ' ) ; do
        ssh -i $WORKER_SSH_KEY $ssh_user@$ip "mkdir -p ~/.ssh ; chmod 700 ~/.ssh"
        scp -i $WORKER_SSH_KEY new_key $ssh_user@$ip:~/.ssh/id_rsa
        scp -i $WORKER_SSH_KEY new_key.pub $ssh_user@$ip:~/.ssh/id_rsa.pub
        ssh -i $WORKER_SSH_KEY $ssh_user@$ip "echo $pub_key >> ~/.ssh/authorized_keys; chmod 400 ~/.ssh/id_rsa; chmod 400 ~/.ssh/id_rsa.pub; chmod 400 ~/.ssh/authorized_keys"
    done
done

sed -i '/instance_ip=/d' "$ENV_FILE"
echo "export INSTANCE_IDS=\"$INSTANCE_IDS\"" >> "$ENV_FILE"
echo "export instance_ip=\"$instance_ip\"" >> "$ENV_FILE"
echo -e "$env_export" >> $ENV_FILE
