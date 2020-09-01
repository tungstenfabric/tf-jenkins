#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x
set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

echo "INFO: Test sanity started"

cat << EOF > $WORKSPACE/test-sanity.sh
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
set -x
echo "openstack version 123 $OPENSTACK_VERSION"
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export ORCHESTRATOR=$ORCHESTRATOR
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export SSL_ENABLE=$SSL_ENABLE
export TF_TEST_IMAGE="$TF_TEST_IMAGE"
export PATH=\$PATH:/usr/sbin
echo "openstack version 123 $OPENSTACK_VERSION"
echo "tf test image 123 $TF_TEST_IMAGE"
src/tungstenfabric/tf-dev-test/contrail-sanity/run.sh
EOF
chmod a+x $WORKSPACE/test-sanity.sh

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/test-sanity.sh} $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./test-sanity.sh || res=1

echo "INFO: Test sanity finished"
exit $res
