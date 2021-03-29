#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" {$WORKSPACE/src,$my_dir/preserve_frozens.sh} $IMAGE_SSH_USER@$instance_ip:./

export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-"tf-nexus.tfci.progmaticlab.com:5001"}

echo "INFO: preserve frozens started"
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin

export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
./src/tungstenfabric/tf-dev-env/common/setup_docker.sh

# to get DISTRO env variable
source ./src/tungstenfabric/tf-dev-env/common/common.sh
# setup additional packages
if [ x"\$DISTRO" == x"ubuntu" ]; then
  export DEBIAN_FRONTEND=noninteractive
  sudo -E apt-get install -y jq curl
else
  sudo yum -y install epel-release
  sudo yum install -y jq curl
fi

./preserve_frozens.sh
EOF
echo "INFO: Update tpc finished"
