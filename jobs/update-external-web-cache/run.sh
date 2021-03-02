#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" {$WORKSPACE/src,$my_dir/update_external_web_cache.sh} $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: Update external web cache started"
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export TPC_REPO_USER=$TPC_REPO_USER
export TPC_REPO_PASS=$TPC_REPO_PASS

export EXTERNAL_WEB_CACHE_REPO=http://tf-nexus.progmaticlab.com/repository/external-web-cache
export CACHE_DIR='external-web-cache'

./update_external_web_cache.sh
EOF
echo "INFO: Update external web cache finished"
