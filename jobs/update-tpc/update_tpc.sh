#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

echo "INFO: run dev-env and sync sources"
./src/tungstenfabric/tf-dev-env/run.sh fetch

echo "INFO: List packages"
sudo docker exec -i tf-dev-sandbox /bin/bash -c "cd contrail/third_party/contrail-third-party-packages/upstream/rpm; make list"
echo "INFO: Prepare for build"
sudo docker exec -i tf-dev-sandbox /bin/bash -c "cd contrail/third_party/contrail-third-party-packages/upstream/rpm; make prep"
echo "INFO: Make all"
sudo docker exec -i tf-dev-sandbox /bin/bash -c "cd contrail/third_party/contrail-third-party-packages/upstream/rpm; make all"
echo "INFO: Copy built RPM-s from container to host"
sudo docker cp tf-dev-sandbox:/root/contrail/third_party/RPMS .

echo "INFO: Upload packages"
for pfile in $(find ./RPMS -type f -name "*.rpm"); do
  package=$(echo $pfile | awk -F '/' '{print $NF}')
  echo "INFO: Upload $pfile as $package"
  curl -s -u ${TPC_REPO_USER}:${TPC_REPO_PASS} --upload-file $pfile $REPO_SOURCE/$package
done
