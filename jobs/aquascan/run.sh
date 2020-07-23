#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/../../infra/${SLAVE}/functions.sh"

AQUASEC_HOST_IP=$(get_instance_ip $AQUASCAN_INSTANCE_NAME)
SCAN_REPORTS_STASH=/tmp/scan_reports

env_file="$WORKSPACE/scan.env"
cat <<EOF > $env_file
CONTAINER_REGISTRY=$CONTAINER_REGISTRY
CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX
DEVENV_IMAGE_NAME=tf-dev-sandbox
SCAN_REPORTS_STASH=${SCAN_REPORTS_STASH}
SCAN_THRESHOLD=9.8
AQUASEC_HOST_IP=$AQUASEC_HOST_IP
AQUASEC_VERSION=4.6
AQUASEC_REGISTRY=registry.aquasec.com
AQUASEC_REGISTRY_USER=$AQUASEC_USERNAME
AQUASEC_REGISTRY_PASSWORD=$AQUASEC_PASSWORD
SCANNER_USER=$AQUASEC_SCANNER_USERNAME
SCANNER_PASSWORD=$AQUASEC_SCANNER_PASSWORD
EOF

scp -i $WORKER_SSH_KEY $SSH_OPTIONS $env_file $my_dir/{scan.sh,excel.py,new_cves.py} $AQUASEC_HOST_USERNAME@$AQUASEC_HOST_IP:

echo "INFO: Prepare the Aquasec environment"
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $AQUASEC_HOST_USERNAME@$AQUASEC_HOST_IP
export WORKSPACE=\$HOME
[ "${DEBUG,,}" == "true" ] && set -x
export PATH=\$PATH:/usr/sbin

DISTRO=$(cat /etc/*release | egrep '^ID=' | awk -F= '{print $2}' | tr -d \")
# setup additional packages
if [ x"\$DISTRO" == x"ubuntu" ]; then
  export DEBIAN_FRONTEND=noninteractive
  sudo -E apt-get install -y jq curl
else
  sudo yum -y install epel-release
  sudo yum install -y jq curl
fi
sudo docker system prune -a -f || true

EOF

echo "INFO: Start scanning containers"
suffix=$(date --utc +"%Y-%m-%dT%H-%M-%S")
scan_report=aquasec-report-${suffix}.xlsx
new_cves_report=aquasec-new-cves-${suffix}.xlsx
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $AQUASEC_HOST_USERNAME@$AQUASEC_HOST_IP
export WORKSPACE=\$HOME
source ./scan.env
if sudo -E ./scan.sh; then
  i="${CONTAINER_REGISTRY}/tf-container-builder-src:${CONTAINER_TAG}"
  if sudo -E docker pull \${i} >/dev/null ; then
    I=\$(sudo -E docker create \${i} cat)
    sudo -E docker cp \${I}:/src/security_vulnerabilities_whitelist ${SCAN_REPORTS_STASH}/
    sudo -E docker rm -f \${I}
    sudo -E docker image rm -f \${i}
    sudo -E python ./new_cves.py -i ${SCAN_REPORTS_STASH} -o $new_cves_report \
      -w ${SCAN_REPORTS_STASH}/security_vulnerabilities_whitelist
  fi

  sudo -E python ./excel.py -i ${SCAN_REPORTS_STASH} -o $scan_report
fi
EOF
rsync -a --remove-source-files -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $AQUASEC_HOST_USERNAME@$AQUASEC_HOST_IP:$scan_report . || true
if -e ${new_cves_report}; then
  rsync -a --remove-source-files -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $AQUASEC_HOST_USERNAME@$AQUASEC_HOST_IP:$new_cves_report .
  echo "ERROR: new CVE-s are detected!"
  exit 1
fi
echo "INFO: Scanning containers is done"
