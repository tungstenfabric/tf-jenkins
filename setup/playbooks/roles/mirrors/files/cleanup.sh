#!/bin/bash

protected_list=''
for symlink in $(find /var/local/mirror/repos/ -type l); do
    protected_list+=$(readlink -f ${symlink})
    protected_list+=' '
done

echo "INFO: List of active directories: $protected_list"

for dir in $(find /var/local/mirror/repos/ -type d -regextype posix-extended -regex ".*20[0-9]{6}$" -mtime +1); do
    if [[ $protected_list =~ $dir ]]; then
       echo "INFO: $dir is using. Skipping"
    else 
       echo "INFO: $dir is old and not active (no symlinks). Deleting"
       rm -rf $dir
    fi
done

