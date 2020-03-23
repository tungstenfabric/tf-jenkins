// This pipeline is temporary used for debugging
// concurent gaing
// if you have a question write here: itimofeev@progmaticlab.com
import groovy.json.JsonOutput;

// constansts
TIMEOUT_HOURS = 4
REGISTRY_IP = "pnexus.sytes.net"
REGISTRY_PORT = "5001"
LOGS_HOST = "pnexus.sytes.net"
LOGS_BASE_PATH = "/var/www/logs/jenkins_logs"
LOGS_BASE_URL = "http://pnexus.sytes.net:8082/jenkins_logs"
if (env.GERRIT_PIPELINE == 'nightly') {
  TIMEOUT_HOURS = 6
  REGISTRY_PORT = "5002"
}

// pipeline flow variables
// base url for all jobs
logs_url = ""
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
        gerrit_utils = load("${WORKSPACE}/tf-jenkins/pipelines/utils/gerrit.groovy")
        config_utils = load("${WORKSPACE}/tf-jenkins/pipelines/utils/config.groovy")
        jobs_utils = load("${WORKSPACE}/tf-jenkins/pipelines/utils/jobs.groovy")
      }

      // TODO Uncommend when concurrent pipeline will be ready
      //if (env.GERRIT_PIPELINE == 'gate' && !gerrit_utils.has_gate_approvals()) {
      //      println("There is no gate approvals.. skip gate")
      //      return
      //}

      def streams = [:]
      def jobs = [:]
      def post_jobs = [:]
      pre_build_done = false
      try {
        time_start = (new Date()).getTime()
        stage('Pre-build') {
          terminate_previous_runs()
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

        println("DEBUG: Jobs = ${jobs}")

        def fetch_sources_count = jobs.count { return it.value['job-name'] == 'fetch-sources' }

        if (env.GERRIT_PIPELINE == 'gate_concurrent'){
          println("DEBUG: Gate concurrent detect")
          // Choose base image for gating pipeline if
          // some gating builds are in process
          builds_map = create_gate_builds_map()
          println("INFO: prepare builds_map = ${builds_map} ")
          set_devenv_tag(builds_map)

// Run fetch_sources - remove after debugging
          jobs_utils.run_jobs(["fetch-sources-centos":["job-name":"fetch-sources"]])

          //  sleep(3600)
          return
        }

        jobs_utils.run_jobs(jobs)
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

        jobs_utils.run_jobs(post_jobs)

        save_pipeline_output_to_logs()
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

def evaluate_env() {
  try {
    sh """#!/bin/bash -e
      echo "export PIPELINE_BUILD_TAG=${BUILD_TAG}" > global.env
      echo "export SLAVE=${SLAVE}" >> global.env
    """

    // evaluate logs params
    if (env.GERRIT_CHANGE_ID) {
      contrail_container_tag = env.GERRIT_CHANGE_NUMBER + '-' + env.GERRIT_PATCHSET_NUMBER
      hash = env.GERRIT_CHANGE_NUMBER.reverse().take(2).reverse()
      logs_path = "${LOGS_BASE_PATH}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/${env.GERRIT_PIPELINE}_${BUILD_NUMBER}"
      logs_url = "${LOGS_BASE_URL}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/${env.GERRIT_PIPELINE}_${BUILD_NUMBER}"
    } else if (env.GERRIT_PIPELINE == 'nightly') {
      contrail_container_tag = 'nightly'
      logs_path = "${LOGS_BASE_PATH}/nightly/pipeline_${BUILD_NUMBER}"
      logs_url = "${LOGS_BASE_URL}/nightly/pipeline_${BUILD_NUMBER}"
    } else {
      contrail_container_tag = 'dev'
      logs_path = "${LOGS_BASE_PATH}/manual/pipeline_${BUILD_NUMBER}"
      logs_url = "${LOGS_BASE_URL}/manual/pipeline_${BUILD_NUMBER}"
    }
    println("Logs URL: ${logs_url}")
    sh """#!/bin/bash -e
      echo "export LOGS_HOST=${LOGS_HOST}" >> global.env
      echo "export LOGS_PATH=${logs_path}" >> global.env
      echo "export LOGS_URL=${logs_url}" >> global.env
    """
    // store default registry params. jobs can redefine them if needed in own config (VARS).
    sh """#!/bin/bash -e
      echo "export REGISTRY_IP=${REGISTRY_IP}" >> global.env
      echo "export REGISTRY_PORT=${REGISTRY_PORT}" >> global.env
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
    } else if (env.GERRIT_PIPELINE == 'nightly') {
      project_name = "tungstenfabric"
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

  def runningBuilds = Jenkins.getInstanceOrNull().getView('All').getBuilds().findAll() { it.getResult().equals(null) }
  for (rb in runningBuilds) {
    def action = rb.allActions.find { it in hudson.model.ParametersAction }
    if (!action)
      continue
    gerrit_change_number = action.getParameter("GERRIT_CHANGE_NUMBER")
    if (!gerrit_change_number) {
      continue
    }
    change_num = gerrit_change_number.value.toInteger()
    patchset_num = action.getParameter("GERRIT_PATCHSET_NUMBER").value.toInteger()
    if (GERRIT_CHANGE_NUMBER.toInteger() == change_num && GERRIT_PATCHSET_NUMBER.toInteger() > patchset_num) {
      rb.doStop()
      println "Build $rb has been aborted when a new patchset is created"
    }
  }
}

def save_pipeline_output_to_logs() {
  println("BUILD_URL = ${BUILD_URL}consoleText")
  withCredentials(
    bindings: [
      sshUserPrivateKey(credentialsId: 'logs_host', keyFileVariable: 'LOGS_HOST_SSH_KEY', usernameVariable: 'LOGS_HOST_USERNAME')]) {
    sh """#!/bin/bash -e
      set -x
      curl ${BUILD_URL}consoleText > pipelinelog.txt 
      ssh -i ${LOGS_HOST_SSH_KEY} -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${LOGS_HOST_USERNAME}@${LOGS_HOST} "mkdir -p ${logs_path}"
      rsync -a -e "ssh -i ${LOGS_HOST_SSH_KEY} -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" pipelinelog.txt ${LOGS_HOST_USERNAME}@${LOGS_HOST}:${logs_path} 
    """
  }
  archiveArtifacts artifacts: "pipelinelog.txt"
  echo "Output logs saved at ${logs_url}/pipelinelog.txt"
}

// Prepare map of gate pipeline builds for choose
// base gating image if concurent mode enabled
def create_gate_builds_map(){
  def builds_map = [:]
  // Get through all gate's builds
  def job = jenkins.model.Jenkins.instance.getItem('pipeline-gate-opencontrail-concurrent')
  job.builds.each {

    println("DEBUG: build execution is ${it.findAll()}")
    def build = it
    def build_id = build.getEnvVars().BUILD_ID
    def build_status = build.getResult().toString()
    // by defailt we apply failed status to build. It can be changed later
    // after we get VERIFIED flag from global.env
    builds_map[build_id] = [status:build_status]

    def artifactManager =  build.getArtifactManager()

    if (artifactManager.root().isDirectory()) {
      def fileList = artifactManager.root().list()
      fileList.each {
        def file = it
        if(file.toString().contains('global.env')) {
          // extract global.env artifact for each build if exists
          def fileText = it.open().getText()
          fileText.split("\n").each {
            def line = it
            // Check if CONTRAIL_CONTAINER_TAG or DEVENVTAG exists in global.env file
            // store theil values into builds_map
            if(line.contains('CONTRAIL_CONTAINER_TAG')) {
              def container_tag = line.split('=')[1].trim()
              builds_map[build_id]['container_tag'] = container_tag
            }
            if(line.contains('DEVENVTAG')) {
              def devenv_tag = line.split('=')[1].trim()
              builds_map[build_id]['devenv_tag'] = devenv_tag
            }
            if(line.contains('VERIFIED')) {
              def verified = line.split('=')[1].trim()
              builds_map[build_id]['verified'] = verified
            }
          }
        }
      }
    }
    // Check build status based on VERIFIED value from global.env
    println ("DEBUG: builds_map[build_id]['verified'] = ${builds_map[build_id]['verified']}")
    if( build_status == 'FAILED' &&
        builds_map[build_id].containsKey('verified') &&
        builds_map[build_id]['verified'].isInteger() &&
        builds_map[build_id]['verified'].toInteger() > 0){
      builds_map[build_id]['status'] = 'SUCCESS'
    }
    if( build_status == 'SUCCESS'){
      if(! builds_map[build_id].containsKey('verified')){
        builds_map[build_id]['status'] = 'FAILURE'
      } else if(builds_map[build_id]['verified'].isInteger() &&
                builds_map[build_id]['verified'].toInteger() <= 0){
        builds_map[build_id]['status'] = 'FAILURE'
      }
    }
  }
  return builds_map
}

def set_devenv_tag(builds_map){
  println("DEBUG: I'm at set_devenv_tag builds_map = ${builds_map}")
  builds_map.any {
    def build = it.value
    def build_no = it.key
    println("DEBUG: build_no = ${build_no} build = ${build}")
    if(build_no.toInteger() >= BUILD_ID.toInteger()){
      // skip current build or builds start late
      return false
    }
    if(build['status'] == "FAILURE" || build['status'] == "ABORTED" )
      // continue iterate to SUCCESS build or build in progress
      return false
    else if( build['status'] == "SUCCESS")
      // We meet Sucess build - no any DEVENVTAG needed - break loop
      return true
    else
      // We meet inprogress build but perhaps it is already fails
      // it is not failed if build not have devenv_tag
      // or if is_build_fail - recursive function return true
      if(!build.containsKey('devenv_tag') || is_build_fail(build['devenv_tag'])){
        // build is in the process and it is not failed - we can use its image
        // for start next build
        // If build's fetch job not have SUCCESS skip the build
        if(! gate_wait_for_fetch(build_no))
          return false

        sh """#!/bin/bash -e
          echo "export DEVENVTAG=${build['container_tag']}" >> global.env
        """
        archiveArtifacts(artifacts: 'global.env')
        return true
      }
  }
}

def is_build_fail(devenv_tag, builds_map) {
  def is_build_not_fail = false
  builds_map.any {
    def build = it.value
    if(build['container_tag'] != devenv_tag)
      // iterate up to build while we not meet container_tag equal devenv_tag
      return false/run
    else if(build['status'] == 'SUCCESS'){
      // Build is not fail
      is_build_not_fail = true
      return true
    }
    else if(build['status'] == 'FAILURE'){
      // Build has been failed
      return true
    // Here we know - build is not finished yet
    } else if(! build.containsKey('devenv_tag')){
      // Buils is in process and it not based on any DEVENVTAG image
      // therefore it not fails
      is_build_not_fail = true
      return true
    } else{
      // We need one recursive call more to check if this build is not fail
      is_build_not_fail = is_build_fail(build['devenv_tag'],builds_map)
      return true
    }
  }
  return is_build_not_fail
}

// Function look up fetch job for gate pipeline with build_no
// And return true if fetch has been finished successfully
// return false in any other cases
def gate_wait_for_fetch(build_no){
          try{
            sleep (10)
        }catch(Exception e){
        println ("ERROR: First Sleep exception happened ${e}")
        }
  println("DEBUG: Try use as a base build ${build_no}")
  def fetch_jobs = jenkins.model.Jenkins.instance.getItem('fetch-sources').getBuilds()

  // Get the build
  def gate_pipeline = jenkins.model.Jenkins.instance.getItem('pipeline-gate-opencontrail-concurrent')
  def build = null
  println("DEBUG: pipelines list: ${gate_pipeline.getBuilds()}")
  gate_pipeline.getBuilds().any {
    println("DEBUG: check if ${it.getEnvVars().BUILD_ID.toInteger()} == ${build_no.toInteger()}")
    if (it.getEnvVars().BUILD_ID.toInteger() == build_no.toInteger()){
      println("DEBUG: build found: ${build_no}")
      build = it
      return true
    }
  }

  println("DEBUG: Build_no = ${build_no} fetch_jobs = ${fetch_jobs}  build = ${build}")

  // Find fetch-sounces job for our build
  def fetch_job = null
  println("DEBUG: Just before Wait until")
  while( ! fetch_job ){
    println("DEBUG: Just enter Wait until")
    // sleep(5)
    fetch_job = gate_lookup_fetch_job(fetch_jobs, build_no)
    println("DEBUG: fetch_job found = ${fetch_job}")
    println("INFO: Waiting for fetch_job will be started")
    // check if build is not fail at last 5 sec
    // if build is not finished yet,
    // or if it finished it's VERIFY must be more than
    println("DEBUG: check if build is running ${build.getResult().toString()}")
    if(build.getResult() != null){
      // Skip the build if it fails
      if(gate_get_build_state(build) == 'FAILURE')
        println "INFO: Build ${build} fails before fetch job is finishes"
        return false
    }
  }

  println("DEBUG: We've got fetch job is : ${fetch_job}   ${fetch_job.class}")
  println("DEBUG: Result of fetch job is : ${fetch_job.getResult()}")

  // Wait for fetch job finished
  while(fetch_job.getResult().toString() == "null"){
    println("INFO: Waiting for fetch job will finished")
    try{
           sleep(20)
    }catch(Exception e){
        println ("ERROR: Sleep exception happened ${e}")
    }
  }

  //waitUntil {
  //  fetch_job.getResult().toString() != "null"
  //}

  //waitUntil {
  //  println("INFO: Waiting for fetch job will finished fetch_job.getResult().toString -> ${fetch_job.getResult().toString() != "null"}")
  //  return fetch_job.getResult().toString() != "null"
  //}

  println("DEBUG: Fetch job ${fetch_job} finishes with result ${fetch_job.getResult()} ")

  return (fetch_job.getResult() == "SUCCESS")?true:false
}

// Function look up fetch-sources job for gate pipeline build with no build_no
def gate_lookup_fetch_job(fetch_jobs, build_no){
  def res = null

  for (job in fetch_jobs) {
    def cause = job.getCause(Cause.UpstreamCause)
    if(cause.getUpstreamProject() == 'pipeline-gate-opencontrail-concurrent' &&
       cause.getUpstreamBuild().toInteger() == build_no.toInteger()){
          // We have found our fetch the job needed
          res = job
       }
  }
  return res
}

// The function get builds artifacts, find there VERIFIED,
// and check if it is integer and more than 0 return SUCCESS
// and return FAILRUE in another case
// !!! Works only if build has been finished! Check getResult() before call this function
def gate_get_build_state(build){
    def result = "FAILURE"
    def artifactManager =  build.getArtifactManager()
    if (artifactManager.root().isDirectory()) {
      def fileList = artifactManager.root().list()
      fileList.each {
        def file = it
        if(file.toString().contains('global.env')) {
          // extract global.env artifact for each build if exists
          def fileText = it.open().getText()
          fileText.split("\n").each {
            def line = it
            if(line.contains('VERIFIED')) {
              def verified = line.split('=')[1].trim()
              if(verified.isInteger() && verified.toInteger() > 0)
                result = "SUCCESS"
            }
          }
        }
      }
    }else{
      println("DEBUG: Not found artifact directory - suppose build fails")
    }
  return result
}