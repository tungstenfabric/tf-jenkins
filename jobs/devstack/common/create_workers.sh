#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"

if [[ -z "$NODES" ]]; then
    echo "NODES declaration error: \"$NODES\""
    echo "creating one controller"
    NODES="CONTROLLER_NODES:$VM_TYPE:1"
fi

rm -f new_key new_key.pub
ssh-keygen -t rsa -N "" -f new_key
pub_key=$(cat new_key.pub)
env_export=""; instance_ip=""; ssh_user=""
all_ips=""

for nodes in $( echo $NODES | tr ',' ' ' ) ; do
    if [[ "$(echo "$nodes" | tr -cd ':' | wc -m)" != 2 ]]; then
        echo "ERROR: inappropriate input \"$nodes\" in \"$NODES\""
        exit 1
    fi

    nodes_type_name="$(echo $nodes | cut -d ':' -f1)"
    export WORKER_NAME_PREFIX="$(echo ${nodes_type_name,,} | tr '_' ' ' |
        awk '{for(i=1;i<=NF;i++) $i=substr($i,1,1)}1' | tr -d ' ')"
    export VM_TYPE="$(echo $nodes | cut -d ':' -f2)"
    export NODES_COUNT="$(echo $nodes | cut -d ':' -f3)"

    if [[ -z "$WORKER_NAME_PREFIX" || -z "$NODES_COUNT" ]]; then
        echo "ERROR: one of parameters is empty in NODES=$NODES [$nodes]"
        exit 1
    elif ! "$my_dir/../../../infra/${SLAVE}/create_workers.sh" ; then
        echo "ERROR: Instances were not created. Exit"
        exit 1
    fi

    INSTANCE_IDS+="$(cat $ENV_FILE | grep INSTANCE_IDS | cut -d'=' -f2)"
    NEW_NODES="$(cat $ENV_FILE | grep INSTANCE_IPS | cut -d'=' -f2)"
    all_ips+="$NEW_NODES"
    # here is string added like CONTROLLER_NODES="some new nodes"
    env_export+="export $nodes_type_name=\"$NEW_NODES\"\n"
    if [[ "${USE_DATAPLANE_NETWORK,,}" == "true" && "$nodes_type_name" == "CONTROLLER_NODES" ]]; then
        control_nodes="$(cat $ENV_FILE | grep DATA_NET_IPS | cut -d'=' -f2)"
        env_export+="export CONTROL_NODES=\"$control_nodes\"\n"
    fi
    [[ -n $ssh_user ]] || ssh_user="$(cat $ENV_FILE | grep IMAGE_SSH_USER | cut -d'=' -f2)"
    [[ -n $instance_ip ]] || instance_ip="$(echo $NEW_NODES | cut -d',' -f1)"
    sed -i '/INSTANCE_IDS=/d' "$ENV_FILE"
    sed -i '/INSTANCE_IPS=/d' "$ENV_FILE"
    sed -i '/DATA_NET_IPS=/d' "$ENV_FILE"
    for ip in $( echo $NEW_NODES | tr ',' ' ' ) ; do
        ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $ssh_user@$ip "mkdir -p ~/.ssh ; chmod 700 ~/.ssh" 2>/dev/null
        scp -i $WORKER_SSH_KEY $SSH_OPTIONS new_key $ssh_user@$ip:~/.ssh/id_rsa 2>/dev/null
        scp -i $WORKER_SSH_KEY $SSH_OPTIONS new_key.pub $ssh_user@$ip:~/.ssh/id_rsa.pub 2>/dev/null
        ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $ssh_user@$ip "echo $pub_key >> ~/.ssh/authorized_keys; chmod 400 ~/.ssh/id_rsa; chmod 400 ~/.ssh/id_rsa.pub; chmod 400 ~/.ssh/authorized_keys" 2>/dev/null
    done
done

# DNS in vexxhost is not stable and we can't rely on it (juju-ha is most critical)
# so fill /etc/hosts on all nodes with all nodes to be sure that name resolution works
hosts="\n"
for ip in $(echo $all_ips | tr ',' ' ') ; do
    echo "INFO: collect hostname from node $ip"
    hostname=$(ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $ssh_user@$ip "hostname -s" 2>/dev/null)
    hosts+="$ip    $hostname\n"
done
echo "INFO: addition to /etc/hosts for all VM-s:"
printf "$hosts"
for ip in $(echo $all_ips | tr ',' ' ') ; do
    echo "INFO: update /etc/hosts on node $ip"
    ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $ssh_user@$ip "sudo bash -c 'printf \"$hosts\" >> /etc/hosts'" 2>/dev/null
done

sed -i '/instance_ip=/d' "$ENV_FILE"
echo "export INSTANCE_IDS=\"$INSTANCE_IDS\"" >> "$ENV_FILE"
echo "export instance_ip=\"$instance_ip\"" >> "$ENV_FILE"
echo -e "$env_export" >> $ENV_FILE
