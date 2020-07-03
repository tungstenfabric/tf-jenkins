#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

NODES=${NODES:-"$VM_TYPE:1"}

# commas and colons are needed for calculation of NODES declaration type
commas="$(echo "$NODES" | tr -cd ',' | wc -m)"

i=1; env_export=""; instance_ip=""

if [[ -z $NODES]]; then
    echo "NODES declaration error: \"$NODES\""
    echo "creating one controller"

    export WORKER_NAME_PREFIX="cn"
    export VM_TYPE=$VM_TYPE
    export NODES_COUNT=1

    if ! "$my_dir/../../../infra/${SLAVE}/create_workers.sh" ; then
        echo "ERROR: Instances were not created. Exit"
        exit 1
    fi

    ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
    IDS=`cat $ENV_FILE | grep INSTANCE_IDS | cut -d'=' -f2`
    NEW_NODES=`cat $ENV_FILE | grep INSTANCE_IPS | cut -d'=' -f2`
    env_export="export CONTROLLER_NODES=\"$NEW_NODES\"\n"
    env_export+="export AGENT_NODES=\"$NEW_NODES\"\n"
    sed -i '/INSTANCE_IDS=/d' "$ENV_FILE"
    sed -i '/INSTANCE_IPS=/d' "$ENV_FILE"
    INSTANCE_IDS+="${IDS}"
    instance_ip="$(echo $NEW_NODES | cut -d',' -f1)"
    export NODES=""
fi

nodes=`echo "$NODES" | cut -d',' -f1`

while [ -n "$nodes" ]; do
    if [[ "$(echo "$nodes" | tr -cd ':' | wc -m)" != 2 ]]; then
        echo "input error \"$nodes\" from \"$NODES\""
        exit 1
    fi

    export WORKER_NAME_PREFIX="$(echo $nodes | cut -d ':' -f1)"
    export VM_TYPE="$(echo $nodes | cut -d ':' -f2)"
    export NODES_COUNT="$(echo $nodes | cut -d ':' -f3)"

    if [[ -z "$WORKER_NAME_PREFIX" || -z "$VM_TYPE" || -z "$NODES_COUNT" ]]; then
       "ERROR: one of parameters is empty in NODES=$NODES [$nodes]"
        exit 1
    fi
    if ! "$my_dir/../../../infra/${SLAVE}/create_workers.sh" ; then
        echo "ERROR: Instances were not created. Exit"
        exit 1
    fi

    ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
    IDS=`cat $ENV_FILE | grep INSTANCE_IDS | cut -d'=' -f2`
    NEW_NODES=`cat $ENV_FILE | grep INSTANCE_IPS | cut -d'=' -f2`
    env_export+="export $WORKER_NAME_PREFIX=\"$NEW_NODES\"\n"
    sed -i '/INSTANCE_IDS=/d' "$ENV_FILE"
    sed -i '/INSTANCE_IPS=/d' "$ENV_FILE"
    INSTANCE_IDS+="${IDS}"

    [[ $i == 1 ]] && instance_ip="$(echo $NEW_NODES | cut -d',' -f1)"
    i=$(( $i + 1 ))
    nodes=$([ "$commas" != 0 ] && echo "$NODES" | cut -d',' -f$i || echo "" )
done

sed -i '/instance_ip=/d' "$ENV_FILE"
echo "export INSTANCE_IDS=\"$INSTANCE_IDS\"" >> "$ENV_FILE"
echo "export instance_ip=$instance_ip" >> "$ENV_FILE"
echo -e "$env_export" >> $ENV_FILE
