#!/bin/bash -e

src_dir="$(readlink -e $1)"
project_fqdn="$2"
patchsets_info_file="$(readlink -e $3)"

cd $src_dir/$project_fqdn
for ref in $(cat $patchsets_info_file | jq -r --arg project $project_fqdn '.[] | select(.project == $project) | .ref'); do
  echo "INFO: run 'git fetch $GERRIT_URL/$project_fqdn $ref && git cherry-pick FETCH_HEAD'"
  git fetch $GERRIT_URL/$project_fqdn $ref && git cherry-pick FETCH_HEAD
done
