#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

echo "INFO: Update tpc started"

cat <<EOF > $WORKSPACE/run_update_tpc.sh
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export REPO_SOURCE=$REPO_SOURCE
export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
export TPC_REPO_USER=$TPC_REPO_USER
export TPC_REPO_PASS=$TPC_REPO_PASS
export DEVENV_TAG=$DEVENV_TAG
export PATH=\$PATH:/usr/sbin

function upload_packages() {
    local pkg_path=\$1
    local repo_url=\$2
    local p=""
    for p in \$(find \${pkg_path} -type f -name "*.rpm" ); do
        curl -s -u \${TPC_REPO_USER}:\${TPC_REPO_PASS} --upload-file \${p} \${repo_url}/\$(echo \${p} | awk -F '/' '{print \$NF}')
    done
}

./src/tungstenfabric/tf-dev-env/run.sh fetch
sudo docker exec -i tf-dev-sandbox /bin/bash -c \
     "cd contrail/third_party/contrail-third-party-packages/upstream/rpm; make list; make prep; make all"
sudo docker cp tf-dev-sandbox:/root/contrail/third_party/RPMS .

upload_packages ./RPMS/noarch $REPO_SOURCE
EOF

chmod a+x $WORKSPACE/run_update_tpc.sh

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/run_update_tpc.sh} $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./run_update_tpc.sh || res=1

echo "INFO: Update tpc finished"
exit $res
