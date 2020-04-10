#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

echo 'INFO: Deploy TF with juju'
cat << EOF > $WORKSPACE/run_deploy_tf.sh
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export OPENSTACK_VERSION=$OPENSTACK_VERSION
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export PATH=\$PATH:/usr/sbin
export CLOUD=${CLOUD:-"local"}
source \$HOME/$CLOUD.vars || /bin/true
cd src/tungstenfabric/tf-devstack/juju
ORCHESTRATOR=$ORCHESTRATOR ./run.sh
EOF

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS" {$WORKSPACE/src,$WORKSPACE/run_deploy_tf.sh} $IMAGE_SSH_USER@$instance_ip:./

bash -c "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS $IMAGE_SSH_USER@$instance_ip 'bash ./run_deploy_tf.sh'" || ret=1

echo "INFO: Deploy tf finished"
exit $ret
