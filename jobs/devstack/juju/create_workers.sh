#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

if [[ "$CLOUD" == 'maas' ]] ; then
  if [[ "$SLAVE" != 'vexxhost' ]]; then
    echo "ERROR: current maas cloud works only for vexxhost slave"
    exit 1
  fi
  "$my_dir/../../../infra/openlab2/create_workers.sh"
  ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
  source "$ENV_FILE"
  ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
  rsync -a -e "$ssh_cmd" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./
  cat <<EOF >> $WORKSPACE/run_prepare_maas.sh
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export MAAS_PROFILE=$MAAS_PROFILE
export MAAS_API_KEY=$MAAS_API_KEY
export MAAS_ENDPOINT=$MAAS_ENDPOINT
src/tungstenfabric/tf-jenkins/infra/openlab2/prepare_maas.sh \$HOME/maas.vars
EOF
  chmod a+x $WORKSPACE/run_prepare_maas.sh

  rsync -a -e "$ssh_cmd" $WORKSPACE/run_prepare_maas.sh $IMAGE_SSH_USER@$instance_ip:./
  # run this via eval due to special symbols in ssh_cmd
  eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./run_prepare_maas.sh

else
  "$my_dir/../common/create_workers.sh"
fi
