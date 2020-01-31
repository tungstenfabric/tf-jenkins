#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/functions.sh"

nova list --tags "SLAVE=$SLAVE" --fields tags > result_"$SLAVE" 

if ! cat result_"$SLAVE" | sed "s/'/\n/g" | grep "PipelineBuildTag" | awk -F "=" '{print $2}' | sort | uniq > existing_tags.txt; then
  echo "No running instances"
  exit 0
fi

curl -k -s "${JENKINS_URL}computer/api/xml?tree=computer\[executors\[currentExecutable\[url\]\],oneOffExecutors\[currentExecutable\[url\]\]\]&xpath=//url&wrapper=builds" | \
    xpath -q -e '/builds/url' | sed -e "s#<url>${JENKINS_URL}job/#jenkins-#g" -e 's#/</url>##g' | tr '/' '-' | sort | uniq > running_jobs.txt

if ! cat running_jobs.txt | grep "${JOB_NAME}-${BUILD_NUMBER}"; then
 echo "Input validation failed"
 exit 1
fi

TERMINATION_LIST_TAGS=$(comm -23 existing_tags.txt running_jobs.txt)

if [[ -n "$TERMINATION_LIST_TAGS" ]]; then
  for t in $TERMINATION_LIST_TAGS; do
    TAGS+=(PipelineBuildTag=${t})
  done
  TERMINATION_LIST=$(nova list --tags-any $(IFS=","; echo "${TAGS[*]}") --status ACTIVE --field locked | grep -v 'True' | awk '{print $2}' | grep -v 'ID'  | grep -v "^$" || true)
  if [[ -n "$TERMINATION_LIST" ]]; then
    down_instances $TERMINATION_LIST || true
    nova delete $TERMINATION_LIST
  fi
fi

TERMINATION_LIST=$(openstack server list --status ERROR -c ID -f value)
if [[ -n "$TERMINATION_LIST" ]]; then
  nova delete $TERMINATION_LIST
fi
