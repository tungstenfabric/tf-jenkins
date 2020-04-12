#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
touch "$ENV_FILE"
echo "export ENVIRONMENT_OS=ubuntu18" >> "$ENV_FILE"
echo "export IMAGE_SSH_USER=jenkins" >> "$ENV_FILE"
echo "export instance_ip=192.168.51.5" >> "$ENV_FILE"
echo "export SSH_EXTRA_OPTIONS=\"-o ProxyCommand=\\\"ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -W %h:%p -i \$OPENLAB2_SSH_KEY -l jenkins -p 30002 openlab.tf-jenkins.progmaticlab.com\\\"\"" >> "$ENV_FILE"

cat <<EOF | ssh -i $OPENLAB2_SSH_KEY $SSH_OPTIONS -p 30002 jenkins@openlab.tf-jenkins.progmaticlab.com
[ "${DEBUG,,}" == "true" ] && set -x
export BUILD_TAG=$BUILD_TAG
export PATH=\$PATH:/usr/sbin
virsh destroy vm-maas || /bin/true
virsh undefine vm-maas || /bin/true
rm -f vm-maas
virt-clone --original ubuntu18 --name vm-maas --auto-clone --file vm-maas
virsh start vm-maas
echo "VM is spinned"
EOF

source "$ENV_FILE"

timeout 300 bash -c "\
while /bin/true ; do \
  ssh -i $OPENLAB2_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS $IMAGE_SSH_USER@$instance_ip 'uname -a' && break ; \
  sleep 10 ; \
done"

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

cat <<EOF > $WORKSPACE/run_deploy_maas.sh
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export IPMI_IPS='192.168.51.20 192.168.51.21 192.168.51.22 192.168.51.23 192.168.51.24'
cd \$HOME/src/tungstenfabric/tf-devstack/common
./deploy_maas.sh \$HOME/maas.vars
EOF
chmod a+x $WORKSPACE/run_deploy_maas.sh

rsync -a -e "$ssh_cmd" $WORKSPACE/run_deploy_maas.sh $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./run_deploy_maas.sh
