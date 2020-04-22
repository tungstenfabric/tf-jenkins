// constansts
TIMEOUT_HOURS = 5
REGISTRY_IP = "pnexus.sytes.net"
REGISTRY_PORT = "5001"
LOGS_HOST = "pnexus.sytes.net"
LOGS_BASE_PATH = "/var/www/logs/jenkins_logs"
LOGS_BASE_URL = "http://pnexus.sytes.net:8082/jenkins_logs"
if (env.GERRIT_PIPELINE == 'nightly') {
  TIMEOUT_HOURS = 6
  REGISTRY_PORT = "5002"
}
// this is default LTS release for all deployers
DEFAULT_OPENSTACK_VERSION="queens"

OPENSTACK_VERSIONS = ['ocata', 'pike', 'queens', 'rocky', 'stein', 'train', 'ussuri', 'victoria']

// pipeline flow variables
// base url for all jobs
logs_url = ""
logs_path = ""
// set of result for each job 
job_results = [:]

rnd = new Random()

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
        cleanWs(disableDeferredWipeout: true, notFailBuild: true, deleteDirs: true)
        clone_self()
        gerrit_utils = load("${WORKSPACE}/tf-jenkins/pipelines/utils/gerrit.test.groovy")
        config_utils = load("${WORKSPACE}/tf-jenkins/pipelines/utils/config.groovy")
        jobs_utils = load("${WORKSPACE}/tf-jenkins/pipelines/utils/jobs.groovy")
        gate_utils = load("${WORKSPACE}/tf-jenkins/pipelines/utils/gate.groovy")
      }
      // TODO: remove comment here when gating is ready
      if (env.GERRIT_PIPELINE == 'gate') { // && !gerrit_utils.has_gate_approvals()) {
            println("There is no gate approvals.. skip gate")
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
          terminate_previous_runs()
          if (env.GERRIT_CHANGE_ID) {
            println('Try stop dependet builds')
            //terminate_dependencies_runs(env.GERRIT_CHANGE_ID)
            terminate_dependency(env.GERRIT_CHANGE_ID)
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

        if (env.GERRIT_PIPELINE != 'gate')
          jobs_utils.run_jobs(jobs)
        else
          jobs_utils.run_gating(jobs, gate_utils, gerrit_utils)
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
            jobs_utils.run_jobs(post_jobs)
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
    userRemoteConfigs: [[url: 'https://github.com/progmaticlab/tf-jenkins.git']],
    extensions: [
      [$class: 'CleanBeforeCheckout'],
      [$class: 'CloneOption', depth: 1],
      [$class: 'RelativeTargetDirectory', relativeTargetDir: 'tf-jenkins']
    ]
  ])
}

def evaluate_common_params() {
  // evaluate logs params
  branch = 'master'
  if (env.GERRIT_BRANCH)
    branch = env.GERRIT_BRANCH.split('/')[-1].toLowerCase()
  openstack_version = DEFAULT_OPENSTACK_VERSION
  if (branch in OPENSTACK_VERSIONS)
    openstack_version = branch
  if (env.GERRIT_CHANGE_ID) {
    contrail_container_tag = branch
    // we have to avoid presense of 19xx, 20xx, ... in tag - apply some hack here to indicate current patchset and avoid those strings
    contrail_container_tag += '-' + env.GERRIT_CHANGE_NUMBER.split('').join('.')
    contrail_container_tag += '-' + env.GERRIT_PATCHSET_NUMBER.split('').join('.')
    hash = env.GERRIT_CHANGE_NUMBER.reverse().take(2).reverse()
    logs_path = "${LOGS_BASE_PATH}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/${env.GERRIT_PIPELINE}_${BUILD_NUMBER}"
    logs_url = "${LOGS_BASE_URL}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/${env.GERRIT_PIPELINE}_${BUILD_NUMBER}"
  } else if (env.GERRIT_PIPELINE == 'nightly') {
    contrail_container_tag = "nightly-${branch}"
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
      echo "export REGISTRY_IP=${REGISTRY_IP}" >> global.env
      echo "export REGISTRY_PORT=${REGISTRY_PORT}" >> global.env
      echo "export OPENSTACK_VERSION=${openstack_version}" >> global.env
      echo "export CONTAINER_REGISTRY=${REGISTRY_IP}:${REGISTRY_PORT}" >> global.env
      echo "export CONTRAIL_CONTAINER_TAG=${contrail_container_tag}" >> global.env
    """

    // store gerrit input if present. evaluate jobs
    println("Pipeline to run: ${env.GERRIT_PIPELINE}")
    project_name = env.GERRIT_PROJECT
    if (env.GERRIT_CHANGE_ID) {
      url = gerrit_utils.resolve_gerrit_url()
      sh """#!/bin/bash -e
        echo "export GERRIT_URL=${url}" >> global.env
        echo "export GERRIT_CHANGE_ID=${env.GERRIT_CHANGE_ID}" >> global.env
        echo "export GERRIT_BRANCH=${env.GERRIT_BRANCH}" >> global.env
      """
      gerrit_utils.resolve_patchsets()
    } else if (env.GERRIT_PIPELINE == 'nightly') {
      project_name = "tungstenfabric"
      sh """#!/bin/bash -e
        echo "export GERRIT_BRANCH=master" >> global.env
      """
    }
    archiveArtifacts(artifacts: 'global.env')

    (streams, jobs, post_jobs) = config_utils.get_jobs(project_name, env.GERRIT_PIPELINE)
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

def terminate_previous_runs() {
  if (!env.GERRIT_CHANGE_ID)
    return

  def builds = Jenkins.getInstanceOrNull().getItemByFullName(env.JOB_NAME).getBuilds()
  for (build in builds) {
    if (!build || !build.getResult().equals(null))
      continue
    def action = build.allActions.find { it in hudson.model.ParametersAction }
    if (!action)
      continue
    gerrit_change_number = action.getParameter("GERRIT_CHANGE_NUMBER")
    if (!gerrit_change_number) {
      continue
    }
    change_num = gerrit_change_number.value.toInteger()
    patchset_num = action.getParameter("GERRIT_PATCHSET_NUMBER").value.toInteger()
    if (GERRIT_CHANGE_NUMBER.toInteger() == change_num && GERRIT_PATCHSET_NUMBER.toInteger() > patchset_num) {
      build.doStop()
      println "Build ${build} has been aborted when a new patchset is created"
    }
  }
}

def get_commit_dependencies(commit_message) {
  def commit_dependencies = []
  try {
    def commit_data = commit_message.split('\n')
    for (commit_str in commit_data) {
      if (commit_str.toLowerCase().startsWith( 'depends-on' )) {
        commit_dependencies += commit_str.split(':')[1].trim()
      }
    }
  } catch(Exception ex) {
    println('Unable to parse dependency string')
  }
  return commit_dependencies
}

def terminate_dependency(change_id) {
  def dependent_changes = []
  def message_targets = []
  def builds = Jenkins.getInstanceOrNull().getItemByFullName(env.JOB_NAME).getBuilds()
    for (def build in builds) {
      if (!build || !build.getResult().equals(null))
        continue
      def action = build.allActions.find { it in hudson.model.ParametersAction }
      if (!action)
        continue
      def gerrit_change_commit_message = action.getParameter("GERRIT_CHANGE_COMMIT_MESSAGE")
      if (!gerrit_change_commit_message) {
        continue
      }
      def encoded_byte_array = gerrit_change_commit_message.value.decodeBase64()
      String commit_message = new String(encoded_byte_array)
      def commit_dependencies = get_commit_dependencies(commit_message)
      if (commit_dependencies.contains(change_id)){
        target_patchset = action.getParameter("GERRIT_PATCHSET_NUMBER").value
        target_change = action.getParameter("GERRIT_CHANGE_ID").value
        target_branch = action.getParameter("GERRIT_BRANCH").value
        message_targets += [target_patchset, target_change, target_branch]
        dependent_changes += target_change
        //build.doStop()
        println('Dependent build' + " " + build + " " + 'has been aborted when a new patchset is created')
      }
    }
  builds = null
  if (message_targets.size() > 0){
    for (target in message_targets) {
      def params = []
      params = target.split(', ')
      try {
        def msg = """Dependent build was started. This build has been aborted"""
        gerrit_utils.notify_gerrit(msg, verified=0, submit=false, params[0], params[1], params[2])
      } catch (err) {
        println("Failed to provide comment to gerrit")
        def msg = err.getMessage()
        if (msg != null) {
          println(msg) 
        }
      }
    }
  }
  println(dependent_changes)
  return
}

def terminate_dependencies_runs(gerrit_change) {
  println('Search for dependent builds')
  def change_ids = terminate_dependency(gerrit_change)
  if ( change_ids.size() > 0 ) {
    for (change_id in change_ids) {
      terminate_dependencies_runs(change_id)
    }
  }
}

def save_pipeline_artifacts_to_logs(def jobs, def post_jobs) {
  println("BUILD_URL = ${BUILD_URL}consoleText")
  withCredentials(bindings: [sshUserPrivateKey(credentialsId: 'logs_host', keyFileVariable: 'LOGS_HOST_SSH_KEY', usernameVariable: 'LOGS_HOST_USERNAME')]) {
    ssh_cmd = "ssh -i ${LOGS_HOST_SSH_KEY} -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
    sh """#!/bin/bash
      rm -rf artefacfs
      mkdir -p artefacts
      curl ${BUILD_URL}consoleText > artefacts/pipelinelog.log
    """
    def all_jobs = jobs + post_jobs
    for (name in all_jobs.keySet()) {
      def job_number = job_results.get(name).get('number')
      if (job_number < 0)
        continue
      def stream = all_jobs[name].get('stream', name)
      def job_name = all_jobs[name].get('job-name', name) 
      sh """#!/bin/bash
        mkdir -p artefacts/${stream}
        curl ${JENKINS_URL}job/${job_name}/${job_number}/consoleText > artefacts/${stream}/output-${job_name}.log
      """
    }
    sh """#!/bin/bash
      ${ssh_cmd} ${LOGS_HOST_USERNAME}@${LOGS_HOST} "mkdir -p ${logs_path}"
      rsync -a -e "${ssh_cmd}" ./artefacts/ ${LOGS_HOST_USERNAME}@${LOGS_HOST}:${logs_path}
    """
  }
  echo "Output logs saved at ${logs_url}/pipelinelog.txt"
}
