#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

if [[ -z ${TPC_REPO_USER} || -z ${TPC_REPO_PASS} ]] ; then
  echo "ERROR: Please define variables TPC_REPO_USER and TPC_REPO_PASS. Exiting..."
  exit 1
fi

sudo yum install -y wget curl gcc python3 python3-setuptools python3-devel python3-lxml
curl --retry 3 --retry-delay 10 https://bootstrap.pypa.io/get-pip.py | sudo python3

# tf-container-build cache

export CACHE_DIR="$(pwd)/external_web_cache"
echo "INFO: download cache for tf-container-builder/containers/populate_external_web_cache.sh"
./src/tungstenfabric/tf-container-builder/containers/populate_external_web_cache.sh

echo "INFO: Upload external-web-cache files"
pushd $CACHE_DIR
for file in $(find . -type f) ; do
  echo "INFO: upload $file"
  curl -s --user "${TPC_REPO_USER}:${TPC_REPO_PASS}" --ftp-create-dirs -T $file $REPO_SOURCE/external-web-cache/$file
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
  curl -s --user "${TPC_REPO_USER}:${TPC_REPO_PASS}" --ftp-create-dirs -T $file $REPO_SOURCE/contrail-third-party/$file
done
popd

# tpc binary cache

CACHE_DIR="$(pwd)/tpc-binary"
mkdir -p $CACHE_DIR
pushd $CACHE_DIR

kernels=( \
  https://vault.centos.org/7.7.1908/os/x86_64/Packages/kernel-3.10.0-1062.el7.x86_64.rpm \
  https://vault.centos.org/7.7.1908/os/x86_64/Packages/kernel-devel-3.10.0-1062.el7.x86_64.rpm \
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-3.10.0-1062.4.1.el7.x86_64.rpm \
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-devel-3.10.0-1062.4.1.el7.x86_64.rpm \
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-3.10.0-1062.9.1.el7.x86_64.rpm \
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-devel-3.10.0-1062.9.1.el7.x86_64.rpm \
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-3.10.0-1062.12.1.el7.x86_64.rpm \
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-devel-3.10.0-1062.12.1.el7.x86_64.rpm \
  https://vault.centos.org/7.8.2003/os/x86_64/Packages/kernel-3.10.0-1127.el7.x86_64.rpm \
  https://vault.centos.org/7.8.2003/os/x86_64/Packages/kernel-devel-3.10.0-1127.el7.x86_64.rpm \
  https://vault.centos.org/7.8.2003/updates/x86_64/Packages/kernel-3.10.0-1127.18.2.el7.x86_64.rpm \
  https://vault.centos.org/7.8.2003/updates/x86_64/Packages/kernel-devel-3.10.0-1127.18.2.el7.x86_64.rpm \
)

for kernel in $kernels ; do
  wget -nv $kernel
done

# todo: download TPC packages somewhere

for file in $(find . -type f) ; do
  echo "INFO: upload $file"
  curl -s --user "${TPC_REPO_USER}:${TPC_REPO_PASS}" --ftp-create-dirs -T $file $REPO_SOURCE/yum-tpc-binary/$file
done
popd
