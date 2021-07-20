// infra and product constants

// docker registry with cleanup policy = 1 day
// all CI check build some images and store them there to check later in deployer
CONTAINER_REGISTRY="tf-nexus.${SLAVE_REGION}.${CI_DOMAIN}:5101"
// base URL for various caches
SITE_MIRROR="http://tf-nexus.${SLAVE_REGION}.${CI_DOMAIN}/repository"
// for ssh purpose
LOGS_HOST = "tf-nexus.${SLAVE_REGION}.${CI_DOMAIN}"
// where to store log files on LOGS_HOST
LOGS_BASE_PATH = "/var/www/logs/jenkins_logs"
// URL to report to user
LOGS_BASE_URL = "http://tf-nexus.${SLAVE_REGION}.${CI_DOMAIN}:8082/jenkins_logs"
// URL to report pipeline result
MONITORING_BACKEND_HOST = "tf-monitoring.${SLAVE_REGION}.${CI_DOMAIN}"
// store built docker images in long-term repo in case of nightly 
if (env.GERRIT_PIPELINE == 'nightly') {
  CONTAINER_REGISTRY="tf-nexus.${SLAVE_REGION}.${CI_DOMAIN}:5102"
}

// possible openstack versions
OPENSTACK_VERSIONS = ['ocata', 'pike', 'queens', 'rocky', 'stein', 'train', 'ussuri', 'victoria', 'wallaby', 'xena']

// in minutes
JOB_TIMEOUT = 180

return this
