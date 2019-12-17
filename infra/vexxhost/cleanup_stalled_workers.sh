#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

API_QUERY_RESULT=$(curl -k -s "${JENKINS_URL}computer/api/xml?tree=computer\[executors\[currentExecutable\[url\]\],oneOffExecutors\[currentExecutable\[url\]\]\]&xpath=//url&wrapper=builds")
echo $API_QUERY_RESULT | grep  ${JOB_NAME} || exit 1
ACTIVE_PIPELINE_BUILDS=$(echo "$API_QUERY_RESULT" | sed  's/<[^>]*>/\n/g'  | sed '/^$/d' | sort | uniq | grep "${PIPELINE_NAME}" | awk -F "/" '{print $(NF-1)}')

if [[ -n "$ACTIVE_PIPELINE_BUILDS" ]]; then
  ACTIVE_TAGS=()
  for b in "$ACTIVE_PIPELINE_BUILDS"; do
    ACTIVE_TAGS+=("xjenkins-${PIPELINE_NAME}-${b}x")
  done
  TERMINATION_LIST=$(nova list --tags "x${PIPELINE_NAME}x" --fields tags | grep -v "^+" | grep -v ID | grep -v "^$" | grep -v -F "${ACTIVE_TAGS}" | tr -d '|[]' | awk '{print $1}' || true)
  if [[ -n "$TERMINATION_LIST" ]]; then
    nova delete $(echo $TERMINATION_LIST | tr '\n' ' ')
  fi
else
  TERMINATION_LIST=$(nova list --tags "x${PIPELINE_NAME}x" --minimal | awk '{print $2}' | grep -v ID | grep -v "^$" || true)
  if [[ -n "$TERMINATION_LIST" ]]; then
      nova delete $(echo $TERMINATION_LIST | tr '\n' ' ')
  fi
fi
