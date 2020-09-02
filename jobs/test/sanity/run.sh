#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

echo "INFO: Test sanity started"

cat << EOF > $WORKSPACE/test-sanity.sh
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export ORCHESTRATOR=$ORCHESTRATOR
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export CONTAINER_REGISTRY_ORIGINAL="$CONTAINER_REGISTRY_ORIGINAL"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export CONTRAIL_CONTAINER_TAG_ORIGINAL="$CONTRAIL_CONTAINER_TAG_ORIGINAL$TAG_SUFFIX"
export SSL_ENABLE=$SSL_ENABLE
export TF_TEST_IMAGE="$TF_TEST_IMAGE"
export PATH=\$PATH:/usr/sbin
src/tungstenfabric/tf-dev-test/contrail-sanity/run.sh
EOF
chmod a+x $WORKSPACE/test-sanity.sh

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/test-sanity.sh} $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./test-sanity.sh || res=1

echo "INFO: Test sanity finished"
exit $res
