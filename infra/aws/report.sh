#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

PIPELINE_INSTANSES=$(aws ec2 describe-instances \
      --region "$AWS_REGION" \
      --filters "Name=tag:SLAVE,Values=${SLAVE}" "Name=instance-state-code,Values=16" \
      --query 'Reservations[].Instances[].InstanceId' \
      --output text)
[[ -z "$PIPELINE_INSTANSES" ]] && exit

for i in $(echo "$PIPELINE_INSTANSES"); do
  TERMINATION_PROTECTION=$(aws ec2 --region "$AWS_REGION" describe-instance-attribute \
    --attribute disableApiTermination \
    --instance-id $i | \
    jq -r '.DisableApiTermination.Value')
  if [[ "$TERMINATION_PROTECTION" == "true" ]]; then
    LOCKED_INSTANCES+=("$i")
  fi
done
[[ "${#LOCKED_INSTANCES[@]}" -lt "1" ]] && exit

MAX_DURATION="259200"
C_DATE=$(date +%s)
for i in $(echo ${LOCKED_INSTANCES[*]}); do
  L_DATE=$(date --date $(aws ec2 describe-instances --region "$AWS_REGION" \
      --query "Reservations[].Instances[].[LaunchTime]" --instance-ids "$i" --output text) +%s)
  DURATION=$(($C_DATE - $L_DATE))
  if [[ "$DURATION" -ge "$MAX_DURATION" ]]; then
   EXCEED+=($i)
  fi
done
[[ "${#EXCEED[*]}" -eq "0" ]] && exit

for h in "${EXCEED[@]}"; do
  i=$(aws ec2 describe-instances --region "$AWS_REGION" \
          --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value | [0]]' \
          --instance-ids "$h" \
          --output text )
  echo "${h} ${i}" >> aws.report.txt
done

if [ -f aws.report.txt ]; then
  echo "VEXXHOST instances alive more than 3 days:" | cat - aws.report.txt | tee aws.report.txt
fi
