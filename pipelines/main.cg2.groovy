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
OPENSTACK_VERSION="queens"

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
        gerrit_utils = load("${WORKSPACE}/tf-jenkins/pipelines/utils/gerrit.groovy")
        config_utils = load("${WORKSPACE}/tf-jenkins/pipelines/utils/config.groovy")
        jobs_utils = load("${WORKSPACE}/tf-jenkins/pipelines/utils/jobs.groovy")
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
          evaluate_logs_params()
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

        if (env.GERRIT_PIPELINE == 'gate'){
          println("DEBUG: Welcome to gate pipeline!!!")

          while(true){
            def base_build_no = gate_utils.save_base_builds()
            try{
              if(gate_utils.is_normal_project()) // Run immediately if normal projest
                jobs_utils.run_jobs(jobs)
              else{ // Wait for the same project pipeline is finishes
                gate_utils.save_pachset_info(base_build_no)
                gate_utils.wait_until_project_pipeline()
                jobs_utils.run_jobs(jobs)
              }
            }catch(Exception ex){
              println("DEBUG: Something fails ${ex}")
              if (! gate_utils.check_build_is_not_failed(BUILD_ID)){
                // If build has been failed - throw exection
                throw new Exception(ex)
              }
            }finally{
              if(base_build_no){
                println("DEBUG: We are found base pipeline ${base_build_no} and waiting when base pipeline will finished")
                gate_utils.wait_pipeline_finished(base_build_no)
                println("DEBUG: Base pipeline has been finished")
                if(gate_utils.check_build_is_not_failed(base_build_no)){
                // Finish the pipeline if base build finished successfully
                // else try to find new base build
                    println("DEBUG: Base pipeline has been verified")
                    break
                  }else{
                    println("DEBUG: Base pipeline has been NOT verified run build again")
                  }
              }else{
                // we not have base build - Just finish the job
                println("DEBUG: We are NOT have base pipeline")
                break
              }
            }
          }
          // jobs_utils.run_jobs(jobs)
        }

       
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

def evaluate_logs_params() {
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
      echo "export OPENSTACK_VERSION=${OPENSTACK_VERSION}" >> global.env
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
