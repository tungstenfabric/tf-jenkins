// infra and product constants

CONTAINER_REGISTRY="tf-nexus.tfci.progmaticlab.com:5001"
SITE_MIRROR="http://tf-nexus.tfci.progmaticlab.com/repository"
LOGS_HOST = "tf-nexus.tfci.progmaticlab.com"
LOGS_BASE_PATH = "/var/www/logs/jenkins_logs"
LOGS_BASE_URL = "http://tf-nexus.tfci.progmaticlab.com:8082/jenkins_logs"
if (env.GERRIT_PIPELINE == 'nightly') {
  CONTAINER_REGISTRY="tf-nexus.tfci.progmaticlab.com:5002"
}
// this is default LTS release for all deployers
DEFAULT_OPENSTACK_VERSION = "queens"

OPENSTACK_VERSIONS = ['ocata', 'pike', 'queens', 'rocky', 'stein', 'train', 'ussuri', 'victoria']

// list of projects which will receive Verified label in gerrit instead of fake VerifiedTF
VERIFIED_PROJECTS = [
  'tungstenfabric/tf-container-builder',
  'tungstenfabric/tf-ansible-deployer',
  'tungstenfabric/tf-charms',
  'tungstenfabric/tf-devstack',
  'tungstenfabric/tf-dev-env',
  'baukin/tf-jenkins',
  'tungstenfabric/tf-dev-test',
  'tungstenfabric/tf-deployment-test'
]

// in minutes
JOB_TIMEOUT = 180

return this
