#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

NODES=${NODES:-"$VM_TYPE:1"}

# commas and colons are needed for calculation of NODES declaration type
commas="$(echo "$NODES" | tr -cd ',' | wc -m)"
colons="$(echo "$NODES" | tr -cd ':' | wc -m)"

# for ex. NODES == "name:type:amount" || NODES == "name1:type1:amount1,name2:type2:amount2"
# || NODES == "name1:type1:amount1,name2:type2:amount2,name3:type3:amouont3" etc.
# so amount of colons is equal to (commas + 1)*2
if [[ $colons -eq $(( $commas*2 + 2 )) ]]; then
    nodes=`echo "$NODES" | cut -d',' -f1`
    i=1; env_export=""
    while [ -n "$nodes" ]; do
        if [[ "$(echo "$nodes" | tr -cd ':' | wc -m)" != 2 ]]; then
            echo "input error \"$nodes\" from \"$NODES\""
            break
        fi
        export WORKER_NAME_PREFIX="$(echo $nodes | cut -d ':' -f1)"
        export VM_TYPE="$(echo $nodes | cut -d ':' -f2)"
        export NODES_COUNT="$(echo $nodes | cut -d ':' -f3)"
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

        i=$(( $i + 1 ))
        nodes=$([ "$commas" != 0 ] && echo "$NODES" | cut -d',' -f$i || echo "" )
    done

    sed -i '/instance_ip=/d' "$ENV_FILE"
    echo "export INSTANCE_IDS=\"$INSTANCE_IDS\"" >> "$ENV_FILE"
    echo -e "$env_export" >> $ENV_FILE

# for ex. NODES == "type:amount" || NODE == "type1:amount1,type2:amount2"
# so amount of colons is equal to commas + 1
elif [[ $colons -eq $(( $commas + 1 )) ]]; then

    controllers=`echo $NODES | cut -d',' -f1`
    export WORKER_NAME_PREFIX='cn'
    export VM_TYPE="$(echo $controllers | cut -d':' -f1)"
    export NODES_COUNT="$(echo $controllers | cut -d':' -f2)"
    if ! "$my_dir/../../../infra/${SLAVE}/create_workers.sh" ; then
        echo "ERROR: Instances were not created. Exit"
        exit 1
    fi

    ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
    CONTROLLER_IDS=`cat $ENV_FILE | grep INSTANCE_IDS | cut -d'=' -f2`
    CONTROLLER_NODES=`cat $ENV_FILE | grep INSTANCE_IPS | cut -d'=' -f2`
    sed -i '/INSTANCE_IDS=/d' "$ENV_FILE"
    sed -i '/INSTANCE_IPS=/d' "$ENV_FILE"

    #support single node case and old behavior
    instance_ip=`echo $CONTROLLER_NODES | cut -d',' -f1`

    AGENT_IDS=""
    AGENT_NODES=$CONTROLLER_NODES
    if [[ $NODES =~ ',' ]] ; then
        agents=`echo $NODES | cut -d',' -f2`
        if [[ -n $agents ]] ; then
            export WORKER_NAME_PREFIX='an'
            export VM_TYPE="$(echo $agents | cut -d':' -f1)"
            export NODES_COUNT="$(echo $agents | cut -d':' -f2)"
            if ! "$my_dir/../../../infra/${SLAVE}/create_workers.sh" ; then
                echo "ERROR: Instances were not created. Exit"
                exit 1
            fi

            AGENT_IDS=`cat $ENV_FILE | grep INSTANCE_IDS | cut -d'=' -f2`
            AGENT_NODES=`cat $ENV_FILE | grep INSTANCE_IPS | cut -d'=' -f2`
            sed -i '/INSTANCE_IDS=/d' "$ENV_FILE"
            sed -i '/INSTANCE_IPS=/d' "$ENV_FILE"
        fi
    fi

    #pass ids and ips to devstack with comma delimeter
    INSTANCE_IDS="$(echo ${CONTROLLER_IDS}${AGENT_IDS})"
    CONTROLLER_NODES="$(echo ${CONTROLLER_NODES})"
    AGENT_NODES="$(echo ${AGENT_NODES})"
    sed -i '/instance_ip=/d' "$ENV_FILE"

    echo "export INSTANCE_IDS=\"$INSTANCE_IDS\"" >> "$ENV_FILE"
    echo "export CONTROLLER_NODES=\"$CONTROLLER_NODES\"" >> "$ENV_FILE"
    echo "export AGENT_NODES=\"$AGENT_NODES\"" >> "$ENV_FILE"
else
    echo "input error \"$NODES\""
    exit 0
fi

#[[ `echo "$INSTANCE_IDS" | tr -cd ',' | wc -m` -gt 1 ]] && export CLOUD="manual"
