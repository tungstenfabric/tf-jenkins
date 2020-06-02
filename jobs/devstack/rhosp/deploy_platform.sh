#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


source "$my_dir/definitions"
stackrc_file=${stackrc_file:-"stackrc.$JOB_NAME.env"}
stackrc_file_path=$WORKSPACE/$stackrc_file

source $stackrc_file_path

echo "INFO: Deploy platform for $JOB_NAME"

cat <<EOF > $WORKSPACE/deploy_platform.sh
#!/bin/bash -e
export RHEL_USER=$RHEL_USER
export RHEL_PASSWORD=$RHEL_PASSWORD
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export PATH=\$PATH:/usr/sbin
source $stackrc_file
EOF

echo "src/tungstenfabric/tf-devstack/${deployer}/run.sh platform" >> $WORKSPACE/deploy_platform.sh
chmod a+x $WORKSPACE/deploy_platform.sh

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/deploy_platform.sh,$stackrc_file_path} $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./deploy_platform.sh || res=1

echo "INFO: Deploy platform finished"
exit $res
