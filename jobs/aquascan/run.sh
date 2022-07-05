#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/../../infra/${SLAVE}/functions.sh"

AQUASEC_HOST="tf-aquascan.$SLAVE_REGION.$CI_DOMAIN"
SCAN_REPORTS_STASH=/tmp/scan_reports

env_file="scan.env"
cat <<EOF > $env_file
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
CONTAINER_REGISTRY=$CONTAINER_REGISTRY
CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX
DEVENV_IMAGE_NAME=tf-dev-sandbox
SCAN_REPORTS_STASH=${SCAN_REPORTS_STASH}
SCAN_THRESHOLD=9.8
AQUASEC_HOST=$AQUASEC_HOST
AQUASEC_VERSION=4.6
AQUASEC_REGISTRY=registry.aquasec.com
AQUASEC_REGISTRY_USER=$AQUASEC_USERNAME
AQUASEC_REGISTRY_PASSWORD=$AQUASEC_PASSWORD
SCANNER_USER=$AQUASEC_SCANNER_USERNAME
SCANNER_PASSWORD=$AQUASEC_SCANNER_PASSWORD
EOF

scp -i $WORKER_SSH_KEY $SSH_OPTIONS $WORKSPACE/$env_file $my_dir/{scan.sh,excel.py,new_cves.py} $AQUASEC_HOST_USERNAME@$AQUASEC_HOST:

echo "INFO: Prepare the Aquasec environment"
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $AQUASEC_HOST_USERNAME@$AQUASEC_HOST
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
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $AQUASEC_HOST_USERNAME@$AQUASEC_HOST
export WORKSPACE=\$HOME
source ./$env_file

sudo locale-gen en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8
source /etc/default/locale
locale

if ! sudo -E ./scan.sh; then
    exit 1
fi
i="\${CONTAINER_REGISTRY}/tf-container-builder-src:\${CONTAINER_TAG}"
if sudo docker pull \${i} >/dev/null ; then
  export PYTHONIOENCODING=utf8
  echo "INFO: pull whitelist from container-builder-src"
  I=\$(sudo docker create \${i} cat)
  sudo docker cp \${I}:/src/security_vulnerabilities_whitelist \${SCAN_REPORTS_STASH}/
  sudo docker rm -f \${I}
  sudo docker image rm -f \${i}
  echo "INFO: prepare filtered report with new CVE-s"
  sudo -E python3 ./new_cves.py -i \${SCAN_REPORTS_STASH} -o $new_cves_report \
    -w \${SCAN_REPORTS_STASH}/security_vulnerabilities_whitelist
fi
echo "INFO: prepare full report"
sudo -E python ./excel.py -i \${SCAN_REPORTS_STASH} -o $scan_report
EOF
rsync -a --remove-source-files -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $AQUASEC_HOST_USERNAME@$AQUASEC_HOST:$scan_report . || true
rsync -a --remove-source-files -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $AQUASEC_HOST_USERNAME@$AQUASEC_HOST:$new_cves_report . 2>/dev/null || true
if [ -e ${new_cves_report} ]; then
  echo "ERROR: new CVE-s are detected: ${FULL_LOGS_URL}/${new_cves_report}"
  exit 1
fi
echo "INFO: Scanning containers is done"
