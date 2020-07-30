#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS"
rsync -a -e "$ssh_cmd" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

./src/tungstenfabric/tf-dev-env/run.sh

sudo docker exec -it tf-dev-sandbox /bin/bash -c \
     "cd contrail/third_party/contrail-third-party-packages/upstream/rpm; make list; make prep; make all"
sudo docker cp tf-dev-sandbox:/root/contrail/third_party/RPMS .
