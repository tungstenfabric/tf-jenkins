
function get_instance_ip() {
  local instance_id=$1
  openstack server show $instance_id -c addresses -f value | cut -f 2 -d '='
}

function list_instances() {
  local tags=$1
  local not_tags=${2:-}
  local opts="--tags ${tags}"
  if [[ -n "$not_tags" ]] ; then
    opts+=" --not-tags $not_tags"
  fi
  nova list $opts --minimal | awk '{print $2}' | grep -v ID | grep -v "^$"
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