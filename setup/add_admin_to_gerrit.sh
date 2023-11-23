#!/bin/bash
# after install of gerrit the first logged in user should get id 100000
# which has admin privilegges
# in fact, while oauth by github is configured, the first user gets id 1000001
# and there is no admin in system
# this script adds mannually user 1000001 to admin group

cd /var/gerrit/git/All-Users.git
git config --global --add safe.directory /var/gerrit/git/All-Users.git
ref_groups=$(git for-each-ref refs/groups)

for rg in $(echo "$ref_groups" | awk '{print$1}') ; do
  group_config=$(git show ${rg}:group.config)
  if echo $group_config | grep "name = Administrators" ; then
    old_commit=$(echo $rg)
    admin_group=$(echo "$ref_groups" | grep $rg | awk '{print$3}')
  fi
done

echo -e '100000\n1000001\n' > members
members_hash=$(git hash-object -w members)
rm members

tree=$(git ls-tree $old_commit)
group_config_hash=$(echo "$tree" | grep "group.config" | awk '{print$3}')
git update-index --add --cacheinfo 100644 $group_config_hash group.config  
git update-index --add --cacheinfo 100644 $members_hash members

new_tree=$(git write-tree)
git config --global user.email "test@example.com"
git config --global user.name "test"

new_commit=$(git commit-tree $new_tree -p $old_commit -m "add admins")

git update-ref $admin_group $new_commit $old_commit
