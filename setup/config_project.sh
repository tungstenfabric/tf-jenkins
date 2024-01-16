#!/bin/bash -x

gerrit_user=$GERRIT_USER
gerrit_host=$GERRIT_HOST

cd /var/gerrit/

# config All-Projects for Verified
mkdir gitproject
cd gitproject
git init
git remote add origin "ssh://$gerrit_user@$gerrit_host:29418/All-Projects"
git fetch origin refs/meta/config:refs/remotes/origin/meta/config
git checkout meta/config
cp project.config ./
git commit -a -m "Added label - Verified"
git push origin meta/config:meta/config
cd ..
rm -rf gitproject

# fill repos
cd git
mkdir tungstenfabric
cd tungstenfabric

repos="tf-analytics \
tf-ansible-deployer \
tf-api-client \
tf-build \
tf-charms \
tf-common \
tf-container-builder \
tf-controller \
tf-deployers-containers \
tf-deployment-test \
tf-dev-env \
tf-dev-test \
tf-devstack \
tf-dpdk \
tf-fabric-utils \
tf-heat-plugin \
tf-helm-deployer \
tf-java-api \
tf-jenkins \
tf-kolla-ansible \
tf-neutron-plugin \
tf-nova-vif-driver \
tf-openlab-ci \
tf-openshift \
tf-openshift-ansible \
tf-operator \
tf-packages \
tf-specs \
tf-test \
tf-third-party \
tf-third-party-cache \
tf-third-party-packages \
tf-tripleo-heat-templates \
tf-tripleo-puppet \
tf-vcenter-fabric-manager \
tf-vcenter-manager \
tf-vcenter-plugin \
tf-vijava \
tf-vnc \
tf-vro-plugin \
tf-vrouter \
tf-vrouter-java-api \
tf-web-controller \
tf-web-core \
tf-webui-third-party"

for repo in $repos ; do
    git clone --mirror git@github.com:tungstenfabric/${repo}.git
done
