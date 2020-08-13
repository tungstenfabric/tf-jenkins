// constansts
TIMEOUT_HOURS = 5
CONTAINER_REGISTRY="nexus.jenkins.progmaticlab.com:5001"
SITE_MIRROR="http://nexus.jenkins.progmaticlab.com/repository"
LOGS_HOST = "nexus.jenkins.progmaticlab.com"
LOGS_BASE_PATH = "/var/www/logs/jenkins_logs"
LOGS_BASE_URL = "http://nexus.jenkins.progmaticlab.com:8082/jenkins_logs"
if (env.GERRIT_PIPELINE == 'nightly') {
  TIMEOUT_HOURS = 6
  CONTAINER_REGISTRY="nexus.jenkins.progmaticlab.com:5002"
}
// this is default LTS release for all deployers
DEFAULT_OPENSTACK_VERSION = "queens"

OPENSTACK_VERSIONS = ['ocata', 'pike', 'queens', 'rocky', 'stein', 'train', 'ussuri', 'victoria']

// pipeline flow variables
// base url for all jobs
logs_url = ""
logs_path = ""
// set of result for each job
job_results = [:]

rnd = new Random()
gerrit_url = null

// gerrit utils
gerrit_utils = null
// config utils
config_utils = null
// jobs utils
jobs_utils = null

timestamps {
  timeout(time: TIMEOUT_HOURS, unit: 'HOURS') {
    node("${SLAVE}") {
      if (!env.GERRIT_CHANGE_ID && env.GERRIT_PIPELINE != 'nightly') {
        println("Manual run is forbidden")
        return
      }

      stage('init') {
        try {
          cleanWs(disableDeferredWipeout: true, notFailBuild: true, deleteDirs: true)
          clone_self()

          gerrit_utils = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/utils/gerrit.groovy")
          if (env.GERRIT_CHANGE_ID) {
            // resolve gerrit_url for further usage
            gerrit_url = gerrit_utils.resolve_gerrit_url()
            // resolve patcchsets
            gerrit_utils.resolve_patchsets()
            // apply patchsets file onto tf-jenkins repo to get latest changes from review if exist
            sh """#!/bin/bash -e
              export GERRIT_URL=${gerrit_url}
              ./src/tungstenfabric/tf-jenkins/infra/gerrit/apply_patchsets.sh ./src tungstenfabric/tf-jenkins ./patchsets-info.json
            """
            // always reload utils (if tf-jenkins in patchset's list)
            gerrit_utils = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/utils/gerrit.groovy")
          }

          config_utils = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/utils/config.groovy")
          jobs_utils = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/utils/jobs.groovy")
          gate_utils = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/utils/gate.groovy")
        } catch (err) {
          verified = gerrit_utils.gerrit_vote(false, null, null, null, null, err.getMessage())
          throw(err)
        }
      }
      if (env.GERRIT_PIPELINE == 'gate' && !gerrit_utils.has_gate_approvals()) {
        println("There is no gate approvals.. skip gate")
        currentBuild.description = "Not ready to gate"
        currentBuild.result = 'UNSTABLE'
        return
      }

      def streams = [:]
      def jobs = [:]
      def post_jobs = [:]
      pre_build_done = false
      try {
        time_start = (new Date()).getTime()
        stage('Pre-build') {
          evaluate_common_params()
          if (env.GERRIT_CHANGE_ID) {
            gerrit_utils.terminate_runs_by_review_number()
            gerrit_utils.terminate_runs_by_depends_on_recursive(env.GERRIT_CHANGE_ID)
          }
          (streams, jobs, post_jobs) = evaluate_env()
          gerrit_utils.gerrit_build_started()

          desc = "<a href='${logs_url}'>${logs_url}</a>"
          if (env.GERRIT_CHANGE_ID) {
            desc += "<br>Project: ${env.GERRIT_PROJECT}"
            desc += "<br>Branch: ${env.GERRIT_BRANCH}"
          }
          currentBuild.description = desc
          pre_build_done = true
        }

        jobs_utils.run(jobs, streams, gate_utils, gerrit_utils)
      } finally {
        println(job_results)
        stage('gerrit vote') {
          // add gerrit voting +2 +1 / -1 -2
          verified = gerrit_utils.gerrit_vote(pre_build_done, streams, jobs, job_results, (new Date()).getTime() - time_start)
          sh """#!/bin/bash -e
            echo "export VERIFIED=${verified}" >> global.env
          """
          archiveArtifacts(artifacts: 'global.env')
        }
        if (pre_build_done)
          try {
            jobs_utils.run_jobs(post_jobs, streams)
          } catch (err) {
          }

        save_pipeline_artifacts_to_logs(jobs, post_jobs)
      }
    }
  }
}


def clone_self() {
  checkout([
    $class: 'GitSCM',
    branches: [[name: "*/master"]],
    doGenerateSubmoduleConfigurations: false,
    submoduleCfg: [],
    userRemoteConfigs: [[url: 'https://github.com/tungstenfabric/tf-jenkins.git']],
    extensions: [
      [$class: 'CleanBeforeCheckout'],
      [$class: 'CloneOption', depth: 1],
      [$class: 'RelativeTargetDirectory', relativeTargetDir: 'src/tungstenfabric/tf-jenkins']
    ]
  ])
}

def evaluate_common_params() {
  // evaluate logs params
  branch = ''
  if (env.GERRIT_BRANCH)
    branch = env.GERRIT_BRANCH.split('/')[-1].toLowerCase()
  openstack_version = DEFAULT_OPENSTACK_VERSION
  if (branch in OPENSTACK_VERSIONS)
    openstack_version = branch
  if (env.GERRIT_CHANGE_ID) {
    contrail_container_tag = branch
    // we have to avoid presense of 19xx, 20xx, ... in tag - apply some hack here to indicate current patchset and avoid those strings
    // and we have to avoid 5.1 and 5.0 in tag
    contrail_container_tag += '-' + env.GERRIT_CHANGE_NUMBER.split('').join('_')
    contrail_container_tag += '-' + env.GERRIT_PATCHSET_NUMBER.split('').join('_')
    hash = env.GERRIT_CHANGE_NUMBER.reverse().take(2).reverse()
    logs_path = "${LOGS_BASE_PATH}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/${env.GERRIT_PIPELINE}_${BUILD_NUMBER}"
    logs_url = "${LOGS_BASE_URL}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/${env.GERRIT_PIPELINE}_${BUILD_NUMBER}"
  } else if (env.GERRIT_PIPELINE == 'nightly') {
    contrail_container_tag = "nightly"
    logs_path = "${LOGS_BASE_PATH}/nightly/pipeline_${BUILD_NUMBER}"
    logs_url = "${LOGS_BASE_URL}/nightly/pipeline_${BUILD_NUMBER}"
  } else {
    contrail_container_tag = 'dev'
    logs_path = "${LOGS_BASE_PATH}/manual/pipeline_${BUILD_NUMBER}"
    logs_url = "${LOGS_BASE_URL}/manual/pipeline_${BUILD_NUMBER}"
  }
  println("Logs URL: ${logs_url}")
}

def evaluate_env() {
  try {
    sh """#!/bin/bash -e
      rm -rf global.env
      echo "export PIPELINE_BUILD_TAG=${BUILD_TAG}" >> global.env
      echo "export SLAVE=${SLAVE}" >> global.env
      echo "export LOGS_HOST=${LOGS_HOST}" >> global.env
      echo "export LOGS_PATH=${logs_path}" >> global.env
      echo "export LOGS_URL=${logs_url}" >> global.env
      # store default registry params. jobs can redefine them if needed in own config (VARS).
      echo "export OPENSTACK_VERSION=${openstack_version}" >> global.env
      echo "export SITE_MIRROR=${SITE_MIRROR}" >> global.env
      echo "export CONTAINER_REGISTRY=${CONTAINER_REGISTRY}" >> global.env
      echo "export DEPLOYER_CONTAINER_REGISTRY=${CONTAINER_REGISTRY}" >> global.env
      echo "export CONTRAIL_CONTAINER_TAG=${contrail_container_tag}" >> global.env
      echo "export CONTRAIL_DEPLOYER_CONTAINER_TAG=${contrail_container_tag}" >> global.env
      echo "export CONTRAIL_CONTAINER_TAG_PIPELINE_ORIGINAL=${contrail_container_tag}" >> global.env
      echo "export GERRIT_PIPELINE=${env.GERRIT_PIPELINE}" >> global.env
    """

    // store gerrit input if present. evaluate jobs
    println("Pipeline to run: ${env.GERRIT_PIPELINE}")
    project_name = env.GERRIT_PROJECT
    if (env.GERRIT_CHANGE_ID) {
      sh """#!/bin/bash -e
        echo "export GERRIT_URL=${gerrit_url}" >> global.env
        echo "export GERRIT_CHANGE_ID=${env.GERRIT_CHANGE_ID}" >> global.env
        echo "export GERRIT_BRANCH=${env.GERRIT_BRANCH}" >> global.env
      """
    } else if (env.GERRIT_PIPELINE == 'nightly') {
      project_name = "tungstenfabric"
      sh """#!/bin/bash -e
        echo "export GERRIT_BRANCH=master" >> global.env
      """
    }
    archiveArtifacts(artifacts: 'global.env')

    (streams, jobs, post_jobs) = config_utils.get_jobs(project_name, env.GERRIT_PIPELINE, env.GERRIT_BRANCH)
    println("Streams from  config: ${streams}")
    println("Jobs from config: ${jobs}")
    println("Post Jobs from config: ${post_jobs}")
  } catch (err) {
    msg = err.getMessage()
    if (err != null) {
      println("ERROR: Failed set environment ${msg}")
    }
    throw(err)
  }
  return [streams, jobs, post_jobs]
}

def save_pipeline_artifacts_to_logs(def jobs, def post_jobs) {
  println("URL of console output = ${BUILD_URL}consoleText")
  withCredentials(bindings: [sshUserPrivateKey(credentialsId: 'logs_host', keyFileVariable: 'LOGS_HOST_SSH_KEY', usernameVariable: 'LOGS_HOST_USERNAME')]) {
    ssh_cmd = "ssh -i ${LOGS_HOST_SSH_KEY} -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
    sh """#!/bin/bash
      curl -s ${BUILD_URL}consoleText > pipelinelog.log
      ${ssh_cmd} ${LOGS_HOST_USERNAME}@${LOGS_HOST} "mkdir -p ${logs_path}"
      rsync -a -e "${ssh_cmd}" pipelinelog.log ${LOGS_HOST_USERNAME}@${LOGS_HOST}:${logs_path}/
    """
  }
  echo "Output logs saved at ${logs_url}/pipelinelog.txt"
}
