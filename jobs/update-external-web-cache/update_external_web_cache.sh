#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

if [[ -z ${TPC_REPO_USER} || -z ${TPC_REPO_PASS} ]] ; then
  echo "ERROR: Please define variables TPC_REPO_USER and TPC_REPO_PASS. Exiting..."
  exit 1
fi

sudo yum install -y wget curl

echo "INFO: run tf-container-builder/containers/populate_external_web_cache.sh"
./src/tungstenfabric/tf-container-builder/containers/populate_external_web_cache.sh


echo "INFO: Upload files"
cd $CACHE_DIR

find . -type f -exec curl --user "${TPC_REPO_USER}:${TPC_REPO_PASS}" --ftp-create-dirs -T {} $EXTERNAL_WEB_CACHE_REPO/{} \;

