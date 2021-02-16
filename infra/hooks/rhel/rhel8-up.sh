rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$my_dir/../../mirrors/mirror-rhel8-all.repo" ${IMAGE_SSH_USER}@${instance_ip}:./local.repo
rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$my_dir/distribute_local_repos.sh" ${IMAGE_SSH_USER}@${instance_ip}:./distribute_local_repos.sh

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
sudo cp -f ./local.repo /etc/yum.repos.d/local.repo

./distribute_local_repos.sh

EOF
