#!/bin/bash -eE
set -o pipefail

# Currently only one worker can be created.

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/definitions"

instance_ip=${INSTANCE_IP[$ENVIRONMENT_OS]}
ipa_mgmt_ip=${IPA_MGMT_IP[$ENVIRONMENT_OS]}
lab=${LAB[$ENVIRONMENT_OS]}

cat <<EOF | ssh -F $my_dir/ssh_config openlab1
[ "${DEBUG,,}" == "true" ] && set -x
#cd /tmp
#rm -rf tf-jenkins
#git clone https://github.com/tungstenfabric/tf-jenkins.git
cd tf-jenkins/contrib/bmc/bmc-cluster-tools/
./reinit-lab.sh $lab
EOF

ssh_config="$(cat $my_dir/ssh_config | base64 -w 0)"
stackrc_file=${stackrc_file:-"stackrc.$JOB_NAME.env"}
echo "export PROVIDER=$PROVIDER" >> "$stackrc_file"
echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$WORKSPACE/$stackrc_file"
echo "export instance_ip=$instance_ip" >> "$WORKSPACE/$stackrc_file"
echo "export mgmt_ip=$instance_ip" >> "$WORKSPACE/$stackrc_file"
echo "export ipa_mgmt_ip=$ipa_mgmt_ip" >> "$WORKSPACE/$stackrc_file"
echo "echo $ssh_config | base64 --decode > \$WORKSPACE/ssh_config " >> "$WORKSPACE/$stackrc_file"
echo "export SSH_EXTRA_OPTIONS=\"-F \$WORKSPACE/ssh_config -J openlab1\"" >> "$WORKSPACE/$stackrc_file"
source "$WORKSPACE/$stackrc_file"

function wait_machine() {
  local addr="$1"
  timeout 300 bash -c "\
  while /bin/true ; do \
    ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS $IMAGE_SSH_USER@$addr 'uname -a' && break ; \
    sleep 10 ; \
  done"
}

wait_machine $instance_ip
ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./
if [[ "${SSL_ENABLE,,}" == 'true' ]] ; then
  wait_machine $ipa_mgmt_ip
fi
