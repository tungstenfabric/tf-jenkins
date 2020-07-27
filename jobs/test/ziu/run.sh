#!/bin/bash -eE
set -o pipefail
set -x
[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

echo "INFO: Test ziu started"

cat << EOF > $WORKSPACE/test-ziu.sh
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export ORCHESTRATOR=$ORCHESTRATOR
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export CONTROLLER_NODES="$CONTROLLER_NODES"
export CONTROLLER_NODES="$(echo $CONTROLLER_NODES | tr ',' ' ')"
export instance_ip=$instance_ip
export SSH_EXTRA_OPTIONS=$SSH_EXTRA_OPTIONS
export IMAGE_SSH_USER=$IMAGE_SSH_USER

export PATH=\$PATH:/usr/sbin
src/tungstenfabric/tf-dev-test/ziu-test/run.sh
EOF
chmod a+x $WORKSPACE/test-ziu.sh

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/test-ziu.sh} $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./test-ziu.sh || res=1

echo "INFO: Test ziu finished"
exit $res
