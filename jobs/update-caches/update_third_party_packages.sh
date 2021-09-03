#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

if [[ -z ${TPC_REPO_USER} || -z ${TPC_REPO_PASS} ]] ; then
  echo "ERROR: Please define variables TPC_REPO_USER and TPC_REPO_PASS. Exiting..."
  exit 1
fi

sudo yum install -y wget curl gcc python3 python3-setuptools python3-devel python3-lxml
curl -fsS --retry 3 --retry-delay 10 https://bootstrap.pypa.io/pip/get-pip.py | sudo python3
sudo python3 -m pip install urllib3

# tf-container-build cache

export CACHE_DIR="$(pwd)/containers_cache"
echo "INFO: download cache for tf-container-builder/containers/populate-cache.sh"
./src/tungstenfabric/tf-container-builder/containers/populate-cache.sh
echo "INFO: download cache for tf-dev-env/container/populate-cache.sh"
./src/tungstenfabric/tf-dev-env/container/populate-cache.sh

echo "INFO: Upload containers cache files"
pushd $CACHE_DIR
for file in $(find . -type f) ; do
  echo "INFO: upload $file"
  curl -fsS --user "${TPC_REPO_USER}:${TPC_REPO_PASS}" --ftp-create-dirs -T $file $REPO_SOURCE/external-web-cache/$file
done
popd

# tf-third-party and tf-webui-third-party caches

function update_third_party_cache() {
  local folder=$1
  local xmlfile=$2
  local cache_folder=$3

  echo "INFO: update cache for $folder/$xmlfile"
  mkdir -p $cache_folder
  pushd $folder
  python3 populate_cache.py $cache_folder $xmlfile
  popd
}

CACHE_DIR="$(pwd)/third_party"
update_third_party_cache src/tungstenfabric/tf-third-party packages.xml $CACHE_DIR
update_third_party_cache src/tungstenfabric/tf-webui-third-party packages.xml $CACHE_DIR
update_third_party_cache src/tungstenfabric/tf-webui-third-party packages_dev.xml $CACHE_DIR

echo "INFO: Upload third-party cached files"
pushd $CACHE_DIR
for file in $(find . -type f) ; do
  echo "INFO: upload $file"
  # ontrail-third-party already in path of downloaded files
  curl -fsS --user "${TPC_REPO_USER}:${TPC_REPO_PASS}" --ftp-create-dirs -T $file $REPO_SOURCE/$file
done
popd

# tpc binary cache

CACHE_DIR="$(pwd)/tpc-binary"
mkdir -p $CACHE_DIR
pushd $CACHE_DIR

# archived packages
kernels="
  https://vault.centos.org/7.6.1810/updates/x86_64/Packages/kernel-3.10.0-957.12.2.el7.x86_64.rpm
  https://vault.centos.org/7.6.1810/updates/x86_64/Packages/kernel-devel-3.10.0-957.12.2.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/os/x86_64/Packages/kernel-3.10.0-1062.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/os/x86_64/Packages/kernel-devel-3.10.0-1062.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-3.10.0-1062.4.1.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-devel-3.10.0-1062.4.1.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-3.10.0-1062.9.1.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-devel-3.10.0-1062.9.1.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-3.10.0-1062.12.1.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-devel-3.10.0-1062.12.1.el7.x86_64.rpm
  https://vault.centos.org/7.8.2003/os/x86_64/Packages/kernel-3.10.0-1127.el7.x86_64.rpm
  https://vault.centos.org/7.8.2003/os/x86_64/Packages/kernel-devel-3.10.0-1127.el7.x86_64.rpm
  https://vault.centos.org/7.8.2003/updates/x86_64/Packages/kernel-3.10.0-1127.18.2.el7.x86_64.rpm
  https://vault.centos.org/7.8.2003/updates/x86_64/Packages/kernel-devel-3.10.0-1127.18.2.el7.x86_64.rpm
  https://vault.centos.org/8.2.2004/BaseOS/x86_64/os/Packages/kernel-4.18.0-193.28.1.el8_2.x86_64.rpm
  https://vault.centos.org/8.2.2004/BaseOS/x86_64/os/Packages/kernel-core-4.18.0-193.28.1.el8_2.x86_64.rpm
  https://vault.centos.org/8.2.2004/BaseOS/x86_64/os/Packages/kernel-devel-4.18.0-193.28.1.el8_2.x86_64.rpm
"

# current packages - should be taken from archive after new release
kernels+="
  http://mirror.centos.org/centos/7/updates/x86_64/Packages/kernel-3.10.0-1160.25.1.el7.x86_64.rpm
  http://mirror.centos.org/centos/7/updates/x86_64/Packages/kernel-devel-3.10.0-1160.25.1.el7.x86_64.rpm
  http://mirror.centos.org/centos/8/BaseOS/x86_64/os/Packages/kernel-4.18.0-305.12.1.el8_4.x86_64.rpm
  http://mirror.centos.org/centos/8/BaseOS/x86_64/os/Packages/kernel-core-4.18.0-305.12.1.el8_4.x86_64.rpm
  http://mirror.centos.org/centos/8/BaseOS/x86_64/os/Packages/kernel-devel-4.18.0-305.12.1.el8_4.x86_64.rpm
"

for kernel in $kernels ; do
  wget -nv $kernel
done

wget -nv -O - https://object-storage.public.mtl1.vexxhost.net/swift/v1/558a8ca6c0484c09b4dc140698842c7a/tf-ci/tpc.tar | tar -xv

for file in $(find . -type f) ; do
  echo "INFO: upload $file"
  curl -fsS --user "${TPC_REPO_USER}:${TPC_REPO_PASS}" --ftp-create-dirs -T $file $REPO_SOURCE/yum-tpc-binary/$file
done
popd
