#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

if [[ -z ${TPC_REPO_USER} || -z ${TPC_REPO_PASS} ]] ; then
  echo "ERROR: Please define variables TPC_REPO_USER and TPC_REPO_PASS. Exiting..."
  exit 1
fi

sudo yum install -y wget curl

rm -rf sanity_images
mkdir -p sanity_images
pushd sanity_images

# this archive already has 'images' prefix in file's path
wget -nv https://object-storage.public.mtl1.vexxhost.net/swift/v1/558a8ca6c0484c09b4dc140698842c7a/tf-ci/images.tgz
tar -xvf images.tgz
rm images.tgz
for file in $(find . -type f) ; do
  echo "INFO: upload $file"
  curl -sS --user "${TPC_REPO_USER}:${TPC_REPO_PASS}" --ftp-create-dirs -T $file $REPO_SOURCE/$file
done

popd
