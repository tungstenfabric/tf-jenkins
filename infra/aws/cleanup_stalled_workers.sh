#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x
set -x
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

aws ec2 describe-instances \
      --region "$AWS_REGION" \
      --filters "Name=instance.group-id,Values=${AWS_SG}" "Name=tag:SLAVE,Values=${SLAVE}" "Name=instance-state-code,Values=16" \
      --query 'Reservations[*].Instances[*].[Tags[?Key==`PipelineBuildTag`].Value | [0]]' \
      --output text | sort | uniq > existing_tags.txt

curl -k -s "${JENKINS_URL}computer/api/xml?tree=computer\[executors\[currentExecutable\[url\]\],oneOffExecutors\[currentExecutable\[url\]\]\]&xpath=//url&wrapper=builds" | \
    xpath -q -e '/builds/url' | sed -e "s#<url>${JENKINS_URL}job/#jenkins-#g" -e 's#/</url>##g' | tr '/' '-' | sort | uniq > running_jobs.txt

if ! cat running_jobs.txt | grep "${JOB_NAME}-${BUILD_NUMBER}"; then
 echo "Input validation failed"
 exit 1
fi

TERMINATION_LIST_TAGS=$(comm -23 existing_tags.txt running_jobs.txt)

if [[ -n "$TERMINATION_LIST_TAGS" ]]; then
  TERMINATION_LIST=$(aws ec2 describe-instances \
      --region "$AWS_REGION" \
      --filters "Name=instance.group-id,Values=${AWS_SG}" \
                "Name=tag:SLAVE,Values=${SLAVE}" \
                "Name=tag:PipelineBuildTag,Values=$(echo ${TERMINATION_LIST_TAGS} | tr ' ' ',')" \
                "Name=instance-state-code,Values=16" \
      --query 'Reservations[*].Instances[*].[InstanceId]' \
      --output text )
  aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids "$TERMINATION_LIST"
fi
