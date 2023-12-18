#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/functions.sh"

nova list --tags "SLAVE=$SLAVE" --fields tags > result_"$SLAVE" 
openstack subnet list --tags "SLAVE=$SLAVE" --long -c Tags -f value >> result_"$SLAVE" 
openstack network list --tags "SLAVE=$SLAVE" --long -c Tags -f value >> result_"$SLAVE" 

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
  TERMINATION_LIST_INSTANCE=$(nova list --tags-any $(IFS=","; echo "${TAGS[*]}") --status ACTIVE --field locked | grep -v 'True' | awk '{print $2}' | grep -v 'ID'  | grep -v "^$" || true)
  if [[ -n "$TERMINATION_LIST_INSTANCE" ]]; then
    down_instances $TERMINATION_LIST_INSTANCE || true
    volumes=$(get_volume_list $TERMINATION_LIST_INSTANCE)
    openstack server delete --wait $TERMINATION_LIST_INSTANCE
    if [[ -n "$volumes" ]] ; then
      openstack volume delete $volumes
    fi
  fi
  TERMINATION_LIST_SUBNET=$(openstack subnet list --any-tags $(IFS=","; echo "${TAGS[*]}") -c ID -f value)
  if [[ -n "$TERMINATION_LIST_SUBNET" ]]; then
    for s in $TERMINATION_LIST_SUBNET; do
      openstack subnet delete $s || true
    done
  fi
  TERMINATION_LIST_NETWORK=$(openstack network list --any-tags $(IFS=","; echo "${TAGS[*]}") -c ID -f value)
  if [[ -n "$TERMINATION_LIST_NETWORK" ]]; then
    for n in $TERMINATION_LIST_NETWORK; do
      openstack network delete $n || true
    done
  fi
fi

TERMINATION_LIST_INSTANCE=$(openstack server list --status ERROR -c ID -f value)
if [[ -n "$TERMINATION_LIST_INSTANCE" ]]; then
  nova delete $TERMINATION_LIST_INSTANCE
fi

TERMINATION_LIST_VOLUME=$(openstack volume list --status available -c ID -f value)
if [[ -n "$TERMINATION_LIST_VOLUME" ]]; then
  sleep 10 # add timeout to wait for not-attached volumes be attached to innstances
  TERMINATION_LIST_VOLUME_NEW=$(openstack volume list --status available -c ID -f value)
  for volume in $TERMINATION_LIST_VOLUME ; do
    if [[ $TERMINATION_LIST_VOLUME_NEW =~ "$volume" ]] ; then
      openstack volume delete $volume
    fi
  done
fi
