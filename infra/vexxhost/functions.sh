
function get_instance_ip() {
  local instance_id=$1
  local net=${2:-"$OS_NETWORK"}

  local networks
  local i
  for (( i=1; i<=5 ; ++i )) ; do
    if networks=$(openstack server show $instance_id -c addresses -f value) 2>/dev/null ; then
      break
    fi
    sleep 10
  done
  if [[ -z "$networks" ]]; then
    return
  fi
  for network in $networks; do
    if [[ " $network" =~ " $net=" ]]; then
      echo $network | cut -d "=" -f 2 | cut -d ";" -f 1 | cut -d "," -f 1
      break
    fi
  done
  # TODO: check that all clients has error handling
}

function get_network_cidr() {
  local net=$1
  local i
  local cidr
  for (( i=1; i<=5 ; ++i )) ; do
    if openstack subnet list --network $net -c Subnet -f value 2>/dev/null | head -1 ; then
      return
    fi
    sleep 10
  done
}

function list_instances() {
  local tags=$1
  local not_tags=${2:-}
  local opts="--tags ${tags}"
  if [[ -n "$not_tags" ]] ; then
    opts+=" --not-tags $not_tags"
  fi
  nova list $opts --minimal | awk '{print $2}' | grep -v ID | grep -v "^$" | tr '\n' ' '
}

function get_tag_value() {
  local instance=$1
  local tag=$2
  local kv=$(nova server-tag-list $instance  | awk '{print $2}' | grep -v "^Tag$" | grep "${tag}=")
  if [[ -n "$kv" ]] ; then
    echo $kv | cut -d '=' -f 2
  fi
}

function tier_down() {
  local instance=$1
  local down=$(get_tag_value $instance DOWN)
  if [[ -n "$down" && -e ${my_dir}/../hooks/${down}/down.sh ]] ; then
    local instance_ip=$(get_instance_ip $instance)
    ${my_dir}/../hooks/${down}/down.sh $instance_ip
  fi
}

function down_instances() {
  echo "INFO: do down nodes"
  local jobs=''
  local i=''
  for i in $@ ; do
    tier_down $i &
    jobs+=" $!"
  done
  for i in $jobs ; do
    wait $i || true
  done
}

function wait_for_free_resources() {
  local required_instances=$1
  local required_cores=$2
  local project_id
  local i
  for (( i=1; i<=5 ; ++i )) ; do
    if project_id=$(openstack project show $OS_PROJECT_NAME | awk '/ id /{print $4}') ; then
      break
    fi
    sleep 10
  done
  if [[ -z "$project_id" ]]; then
    echo "ERROR: Can't get project_id by name $OS_PROJECT_NAME"
    return 1
  fi

  echo "INFO: wait for enough resources for required_instances=$required_instances and required_cores=$required_cores  $(date)"
  while true ; do
    local quotas
    if ! quotas=$(openstack quota list --project $project_id --detail --compute) ; then
      sleep $VM_BOOT_DELAY
      continue
    fi
    local instances_used=$(echo "$quotas" | awk '/ instances /{print $4}')
    local instances_limit=$(echo "$quotas" | awk '/ instances /{print $8}')
    local cores_used=$(echo "$quotas" | awk '/ cores /{print $4}')
    local cores_limit=$(echo "$quotas" | awk '/ cores /{print $8}')
    if (( instances_used + required_instances + RESERVED_INSTANCES_COUNT < instances_limit )) &&
        (( cores_used + required_cores + RESERVED_CORES_COUNT < cores_limit )) ; then
      break
    fi
    echo "INFO: waiting for free resources...  $(date)"
    echo "INFO: instances used=$instances_used  required=$NODES_COUNT  reserved=$RESERVED_INSTANCES_COUNT  limit=$instances_limit"
    echo "INFO: cores used=$cores_used  required=$required_cores  reserved=$RESERVED_CORES_COUNT  limit=$cores_limit"
    sleep $VM_BOOT_DELAY
  done
  echo "INFO: waiting for resources is finished  $(date)"
}
