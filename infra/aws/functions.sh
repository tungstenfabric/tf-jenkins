

function get_instance_ip() {
  local instance_id=$1
  aws ec2 describe-instances \
      --region $AWS_REGION \
      --filters \
      "Name=instance-state-name,Values=running" \
      "Name=instance-id,Values=$instance_id" \
      --query 'Reservations[*].Instances[*].[PrivateIpAddress]' \
      --output text
}

function get_tag_value() {
  local instance=$1
  local tag=$2
  local value=$(aws ec2 describe-instances \
      --region "$AWS_REGION" \
      --instance-id $instance \
      --query "Reservations[*].Instances[*].Tags[?Key=='$tag']" \
      --output text | awk '{print($2)}')
  if [[ -n "$value" ]] ; then
    echo $value
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

function terminate_instance() {
  local instance=$1
  local protected=$(aws ec2 --region "$AWS_REGION" describe-instance-attribute \
        --attribute disableApiTermination \
        --instance-id $instance | \
        jq -r '.DisableApiTermination.Value')
  if [[ "$protected" == "false" ]]; then
    tier_down $instance
    aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids "$instance"
  fi
}

function terminate_instances() {
  echo "INFO: terminate nodes: $@"
  local jobs=''
  local i=''
  for i in $@ ; do
    terminate_instance $i &
    jobs+=" $!"
  done
  for i in $jobs ; do
    wait $i || true
  done 
}
