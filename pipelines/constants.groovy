// infra and product constants

// docker registry with cleanup policy = 1 day
// all CI check build some images and store them there to check later in deployer
CONTAINER_REGISTRY="tf-nexus.${SLAVE_REGION}.${CI_DOMAIN}:5001"
// base URL for various caches
SITE_MIRROR="http://tf-nexus.${SLAVE_REGION}.${CI_DOMAIN}/repository"
// for ssh purpose
LOGS_HOST = "tf-nexus.${SLAVE_REGION}.${CI_DOMAIN}"
// where to store log files on LOGS_HOST
LOGS_BASE_PATH = "/var/www/logs/jenkins_logs"
// URL to report to user
LOGS_BASE_URL = "http://tf-nexus.${SLAVE_REGION}.${CI_DOMAIN}:8082/jenkins_logs"
// store built docker images in long-term repo in case of nightly 
if (env.GERRIT_PIPELINE == 'nightly') {
  CONTAINER_REGISTRY="tf-nexus.${SLAVE_REGION}.${CI_DOMAIN}:5002"
}
// this is default LTS release for all deployers
DEFAULT_OPENSTACK_VERSION = "queens"

// possible openstack versions
OPENSTACK_VERSIONS = ['ocata', 'pike', 'queens', 'rocky', 'stein', 'train', 'ussuri', 'victoria']

// list of projects which will receive Verified label in gerrit instead of fake VerifiedTF
VERIFIED_PROJECTS = [
  'tungstenfabric/tf-container-builder',
  'tungstenfabric/tf-ansible-deployer',
  'tungstenfabric/tf-charms',
  'tungstenfabric/tf-devstack',
  'tungstenfabric/tf-dev-env',
  'tungstenfabric/tf-jenkins',
  'tungstenfabric/tf-dev-test',
  'tungstenfabric/tf-deployment-test'
]

// in minutes
JOB_TIMEOUT = 180

return this
