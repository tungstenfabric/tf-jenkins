#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x
set -x
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
env|sort
API_QUERY_RESULT=$(curl -k -s "${JENKINS_URL}computer/api/xml?tree=computer\[executors\[currentExecutable\[url\]\],oneOffExecutors\[currentExecutable\[url\]\]\]&xpath=//url&wrapper=builds")
echo $API_QUERY_RESULT | grep  "${JOB_NAME}" || exit 1
ACTIVE_PIPELINE_BUILDS=$(echo "$API_QUERY_RESULT" | sed  's/<[^>]*>/\n/g'  | sed '/^$/d' | sort | uniq | grep "${PIPELINE_NAME}" | awk -F "/" '{print $(NF-1)}')
aws ec2 describe-instances \
      --region "$AWS_REGION" \
      --filters "Name=instance.group-id,Values=${AWS_SG}" \
      --query 'Reservations[*].Instances[*].[InstanceId, Tags[?Key==`PipelineBuildTag`].Value | [0]]' \
      --output text | \
      grep "jenkins-${PIPELINE_NAME}" | grep -v -F "${ACTIVE_PIPELINE_BUILDS}" | awk '{print $1}'
if [[ -n "$ACTIVE_PIPELINE_BUILDS" ]]; then
  TERMINATION_LIST=$(aws ec2 describe-instances \
      --region "$AWS_REGION" \
      --filters "Name=instance.group-id,Values=${AWS_SG}" \
      --query 'Reservations[*].Instances[*].[InstanceId, Tags[?Key==`PipelineBuildTag`].Value | [0]]' \
      --output text | \
      grep "jenkins-${PIPELINE_NAME}" | grep -v -F "${ACTIVE_PIPELINE_BUILDS}" | awk '{print $1}')
  if [[ -n "$TERMINATION_LIST" ]]; then
      aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids "$TERMINATION_LIST"
  fi
else
  TERMINATION_LIST=$(aws ec2 describe-instances \
      --region $AWS_REGION \
      --filters "Name=instance.group-id,Values=${AWS_SG}" \
      --filters "Name=PipelineName,Values=${PIPELINE_NAME}" \
      --query 'Instances[*]' \
      --output text)
  if [[ -n "$TERMINATION_LIST" ]]; then
      aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids "$TERMINATION_LIST"
  fi
fi
