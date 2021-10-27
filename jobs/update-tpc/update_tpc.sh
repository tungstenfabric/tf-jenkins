#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

echo "INFO: prepare mirrors input"
mkdir -p ./src/tungstenfabric/tf-dev-env/config/etc
cp pip.conf ./src/tungstenfabric/tf-dev-env/config/etc/pip.conf
# TODO: add yum mirrors: base and docker

echo "INFO: run dev-env and sync sources"
./src/tungstenfabric/tf-dev-env/run.sh fetch

echo "INFO: preapre deps for TPP compilation"
./src/tungstenfabric/tf-dev-env/run.sh configure tpp

echo "INFO: Buil TPP"
./src/tungstenfabric/tf-dev-env/run.sh compile tpp

echo "INFO: Copy built RPM-s from container to host"
sudo docker cp tf-dev-sandbox:/root/contrail/third_party/RPMS .

echo "INFO: Upload packages"
for pfile in $(find ./RPMS -type f -name "*.rpm"); do
  package=$(echo $pfile | awk -F '/' '{print $NF}')
  echo "INFO: Upload $pfile as $package"
  curl -sS -u ${TPC_REPO_USER}:${TPC_REPO_PASS} --upload-file $pfile $REPO_SOURCE/$package
done
