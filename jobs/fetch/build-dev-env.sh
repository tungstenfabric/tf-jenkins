#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

# do it as a latest source to override all exports
if [[ -f ${WORKSPACE}/${JOB_NAME}.env ]]; then
  source ${WORKSPACE}/${JOB_NAME}.env
fi

stable_tag=${STABLE_TAGS["${ENVIRONMENT_OS^^}"]}
target_tag="$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox:$stable_tag"
linux_distr=${TARGET_LINUX_DISTR["$ENVIRONMENT_OS"]}
tf_devenv_container_name=tf-developer-sandbox-${PIPELINE_BUILD_TAG}
commit_name="tf-developer-sandbox-$stable_tag"

#TODO: Rebuild be done only for review for dev-env,
# re-tagging for stable will be done only after successful tests
$WORKSPACE/src/progmaticlab/tf-jenkins/infra/${SLAVE}/create_workers.sh
ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source $ENV_FILE

res=0
rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./ || res=1

if [[ $res == 0 ]] ; then
  echo "INFO: build tf-dev-env started..."
  cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x

export WORKSPACE=\$HOME
export TF_CONFIG_DIR=\$HOME

# dont setup own registry & repo
export CONTRAIL_DEPLOY_REGISTRY=0
export CONTRAIL_DEPLOY_RPM_REPO=0

export REGISTRY_IP=$REGISTRY_IP
export REGISTRY_PORT=$REGISTRY_PORT
export SITE_MIRROR=http://${REGISTRY_IP}/repository

# to not to bind contrail sources to container
export CONTRAIL_DIR=""

export BUILD_DEV_ENV=1
export LINUX_DISTR=$linux_distr
export TF_DEVENV_CONTAINER_NAME=$tf_devenv_container_name
export IMAGE=$REGISTRY_IP:$REGISTRY_PORT/tf-developer-sandbox
export DEVENVTAG=$stable_tag

cd src/tungstenfabric/tf-dev-env
./run.sh none
EOF
  echo "INFO: build tf-dev-env done: res=$res"

  if [[ $res == 0 ]] ; then
    echo "INFO: Save container $target_tag"
    cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x
set -eo pipefail

echo "INFO: commit $tf_devenv_container_name container as $commit_name"
sudo docker commit $tf_devenv_container_name $commit_name

echo "INFO: tag $commit_name container as $target_tag"
sudo docker tag $commit_name $target_tag

echo "INFO: push $target_tag container"
sudo docker push $target_tag
EOF
    echo "INFO: Save container $target_tag done"
  fi
fi

# remove worker as soon as possible to free resources
$WORKSPACE/src/progmaticlab/tf-jenkins/infra/${SLAVE}/remove_workers.sh || true

exit $res
