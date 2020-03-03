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
// list of pure info about jobs from config with additional parameters
jobs_from_config = [:]
// list of top jobs from config: fetch, build, unit, lint
top_jobs_to_run = []
// list of test configurations in format ${deployer}_${orchestrator}
test_configuration_names = []
// set of jobs code for both above
top_jobs_code = [:]
inner_jobs_code = [:]
// set of result of each job 
job_results = [:]

rnd = new Random()

// gerrit utils
gerrit = null

timestamps {
  timeout(time: TIMEOUT_HOURS, unit: 'HOURS') {
    node("${SLAVE}") {
      if (!env.GERRIT_CHANGE_ID && env.GERRIT_PIPELINE != 'nightly') {
        println("Manual run is forbidden")
        return
      }
      clone_self()
      gerrit = load("${WORKSPACE}/tf-jenkins/pipelines/utils/gerrit.groovy")
      // has_gate_approvals needs cloned repo for tools
      println("Verified value to report on success: ${gerrit.VERIFIED_SUCCESS_VALUES[env.GERRIT_PIPELINE]}")
      if (env.GERRIT_PIPELINE == 'gate' && !gerrit.has_gate_approvals()) {
        println("There is no gate approvals.. skip gate")
        return
      }
      pre_build_done = false
      try {
        time_start = (new Date()).getTime()
        stage('Pre-build') {
          terminate_previous_jobs()
          evaluate_env()
          archiveArtifacts(artifacts: 'global.env')
          println "Logs URL: ${logs_url}"
          println 'Top jobs to run: ' + top_jobs_to_run
          println 'Test configurations: ' + test_configuration_names
          gerrit.gerrit_build_started()
          currentBuild.description = "<a href='${logs_url}'>${logs_url}</a>"
          pre_build_done = true
        }

        if ('fetch-sources' in top_jobs_to_run) {
          stage('Fetch') {
            run_job('fetch-sources', [job: 'fetch-sources'])
          }
        }

        // build independent jobs
        ['test-unit', 'test-lint'].each { name ->
          if (name in top_jobs_to_run) {
            top_jobs_code[name] = {
              stage(name) {
                run_job(name, [job: name])
              }
            }
          }
        }

        // declaration of deploy platform parts
        test_configuration_names.each { name ->
          top_jobs_code["Deploy platform for ${name}"] = {
            stage("Deploy platform for ${name}") {
              println "Started deploy platform for ${name}"
              timeout(time: 60, unit: 'MINUTES') {
                run_job("deploy-platform-${name}", [job: "deploy-platform-${name}"])
              }
            }
          }
        }

        // declaration of deploy TF parts and functional tests run after
        test_configuration_names.each { name ->
          inner_jobs_code["Deploy TF for ${name}"] = {
            stage("Deploy TF for ${name}") {
              println "Started deploy TF and test for ${name}"
              // just wait for deploy-platform job - build job just is a previous step
              waitUntil {
                sleep(15)
                return job_results["deploy-platform-${name}"].containsKey('result')
              }
              if (job_results["deploy-platform-${name}"]['result'] != 'SUCCESS') {
                unstable("Deploy platform failed - skip deploy TF and tests for ${name}")
                return
              }

              try {
                top_job_number = job_results["deploy-platform-${name}"]['number']
                run_job("deploy-tf-${name}", [job: "deploy-tf-${name}"])
                def test_jobs = [:]
                gerrit.get_test_job_names(name).each { test_name ->
                  test_jobs["${test_name} for deploy-tf-${name}"] = {
                    stage("${test_name}-${name}") {
                      // next variable must be taken again due to closure limitations for free variables
                      top_job_number = job_results["deploy-platform-${name}"]['number']
                      run_job(
                        "${test_name}-${name}",
                        [job: test_name,
                         parameters: [
                          string(name: 'DEPLOY_PLATFORM_JOB_NAME', value: "deploy-platform-${name}"),
                        ]])
                    }
                  }
                }
                parallel test_jobs
              } finally {
                stage('Collect logs and cleanup') {
                  top_job_number = job_results["deploy-platform-${name}"]['number']
                  println "Trying to collect logs and cleanup workers for ${name} job ${top_job_number}"
                  run_job(
                    "collect-logs-and-cleanup",
                    [job: "collect-logs-and-cleanup",
                     parameters: [
                      string(name: 'DEPLOY_PLATFORM_JOB_NAME', value: "deploy-platform-${name}"),
                    ]])
                }
              }
            }
          }
        }

        // check if build is enabled
        if ('build' in top_jobs_to_run) {
          // add publish job into inner_jobs_code to be run in parallel with deploy but after build
          if (env.GERRIT_PIPELINE == 'nightly') {
            inner_jobs_code["Publish TF containers to docker hub"] = {
              stage('publish-latest') {
                run_job(
                  'publish',
                  [job: 'publish',
                   parameters: [booleanParam(name: 'STABLE', value: false)]])
              }
            }
          }
          top_jobs_code['Build images for testing'] = {
            stage('build') {
              run_job('build', [job: 'build'])
            }
            parallel inner_jobs_code
          }
        } else {
          top_jobs_code['Test with nightly images'] = {
            parallel inner_jobs_code
          }
        }

        // run jobs in parallel
        parallel top_jobs_code
      } finally {
        println "Logs URL: ${logs_url}"
        println "Destroy VMs"
        try {
          run_job('cleanup-pipeline-workers', [job: 'cleanup-pipeline-workers'])
        } catch(err){
        }

        // add gerrit voting +2 +1 / -1 -2
        verified = gerrit.gerrit_vote(pre_build_done, (new Date()).getTime() - time_start)
        if (verified > 0 && env.GERRIT_PIPELINE == 'nightly' && 'build' in top_jobs_to_run) {
          // publish stable
          stage('publish-latest-stable') {
            run_job(
              'publish',
              [job: 'publish', 
               parameters: [booleanParam(name: 'STABLE', value: true)]])
          }
        }

        save_output_to_nexus()
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
      contrail_container_tag = GERRIT_CHANGE_NUMBER + '-' + GERRIT_PATCHSET_NUMBER
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
    sh """#!/bin/bash -e
      echo "export LOGS_HOST=${LOGS_HOST}" >> global.env
      echo "export LOGS_PATH=${logs_path}" >> global.env
      echo "export LOGS_URL=${logs_url}" >> global.env
    """

    // store gerrit input if present. evaluate jobs
    println "Pipeline to run: ${env.GERRIT_PIPELINE}"
    if (env.GERRIT_CHANGE_ID) {
      url = gerrit.resolve_gerrit_url()
      sh """#!/bin/bash -e
        echo "export GERRIT_URL=${url}" >> global.env
        echo "export GERRIT_CHANGE_ID=${env.GERRIT_CHANGE_ID}" >> global.env
        echo "export GERRIT_BRANCH=${env.GERRIT_BRANCH}" >> global.env
      """
      get_jobs(env.GERRIT_PROJECT, env.GERRIT_PIPELINE)
    } else if (env.GERRIT_PIPELINE == 'nightly') {
      get_jobs("tungstenfabric", env.GERRIT_PIPELINE)
    }
    println "Evaluated jobs to run: ${jobs_from_config}"
    def possible_top_jobs = ['test-lint', 'test-unit', 'build', 'fetch-sources']
    for (item in jobs_from_config) {
      if (item.getKey() in possible_top_jobs) {
        top_jobs_to_run += item.getKey()
      } else {
        test_configuration_names += item.getKey()
      }
    }

    // evaluate registry params
    // if we have fetch-sources then it means that we have build stage thus we have to use own registry for deploy
    if ('fetch-sources' in top_jobs_to_run) {
      sh """#!/bin/bash -e
        echo "export REGISTRY_IP=${REGISTRY_IP}" >> global.env
        echo "export REGISTRY_PORT=${REGISTRY_PORT}" >> global.env
        echo "export CONTAINER_REGISTRY=${REGISTRY_IP}:${REGISTRY_PORT}" >> global.env
        echo "export CONTRAIL_CONTAINER_TAG=${contrail_container_tag}" >> global.env
      """
    }
  } catch (err) {
    msg = err.getMessage()
    if (err != null) {
      println "Failed set environment ${msg}"
    }
    throw(err)
  }
}

def get_jobs(project, gerrit_pipeline) {
  def data = readYaml file: "${WORKSPACE}/tf-jenkins/config/projects.yaml"
  def templates = [:]
  for (item in data) {
    if (item.containsKey('project-template')) {
      template = item.get('project-template')
      templates[template.name] = template
    }
  }
  for (item in data) {
    if (!item.containsKey('project') || item.get('project').name != project)
      continue
    project = item.get('project')
    if (project.containsKey('templates')) {
      for (template in project.templates) {
        if (templates[template].get(gerrit_pipeline) && templates[template].get(gerrit_pipeline).get('jobs')) {
          for (job_item in templates[template].get(gerrit_pipeline).jobs) {
            add_job(job_item)
          }
        }
      }
    }
    if (project.get(gerrit_pipeline) && project.get(gerrit_pipeline).get('jobs')) {
      for (job_item in project.get(gerrit_pipeline).jobs) {
        add_job(job_item)
      }
    }
  }
}

def add_job(job_item) {
  if (job_item instanceof String) {
    jobs_from_config[job_item] = [:]
  } else {
    job = job_item.entrySet().iterator().next()
    jobs_from_config[job.getKey()] = job.getValue()
  }
}

def job_params_to_file(job_name, job_rnd) {
  if (!jobs_from_config.containsKey(job_name) || !jobs_from_config[job_name].containsKey('vars'))
    return

  env_file = "vars.${job_name}-${job_rnd}.env"
  env_text = ""
  for (jvar in jobs_from_config[job_name]['vars']) {
    env_text += "export ${jvar.getKey()}='${jvar.getValue()}'\n"
  }
  writeFile(file: env_file, text: env_text)
  archiveArtifacts artifacts: "${env_file}"
}

def run_job(name, params) {
  def job_name = params['job']
  job_results[name] = [:]
  def job = null
  err = null
  try {
    def job_rnd = "${rnd.nextInt(99999)}"
    job_params_to_file(name, job_rnd)
    params['parameters'] = params.get('parameters', []) + [
      string(name: 'RANDOM', value: job_rnd),
      string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
      string(name: 'PIPELINE_NUMBER', value: "${BUILD_NUMBER}"),
      [$class: 'LabelParameterValue', name: 'NODE_NAME', label: "${NODE_NAME}"]]
    job = build(params)
    println "Finished ${name} with SUCCESS"
  } catch (err) {
    println "Failed ${name} with error"
    job_results[name]['result'] = 'FAILURE'
    msg = err.getMessage()
    if (msg != null) {
      println msg
    }
    // get build num from exception and find job to get duration and result
    try {
      def cause_msg = err.getCauses()[0].getShortDescription()
      def build_num_matcher = cause_msg =~ /#\d+/
      if (build_num_matcher.find()) {
        def build_num = ((build_num_matcher[0] =~ /\d+/)[0]).toInteger()
        job = Jenkins.getInstanceOrNull().getItemByFullName(job_name).getBuildByNumber(build_num)
      }
    } catch(e) {
      println("Error in obtaining failed job result ${err.getMessage()}")
    }
  }
  if (job) {
    def job_number = job.getNumber()
    job_results[name]['number'] = job_number
    job_results[name]['duration'] = job.getDuration()
    job_results[name]['result'] = job.getResult()
    copyArtifacts(filter: '*.env', optional: true, fingerprintArtifacts: true, projectName: "${job_name}", selector: specific("${job_number}"))
  }
  // re-throw error
  if (err != null)
    throw(err)
}

def terminate_previous_jobs() {
  if (!env.GERRIT_CHANGE_ID)
    return

  def runningBuilds = Jenkins.getInstanceOrNull().getView('All').getBuilds().findAll() { it.getResult().equals(null) }
  for (rb in runningBuilds) {
    def action = rb.allActions.find {it in hudson.model.ParametersAction}
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

def save_output_to_nexus() {
  println "BUILD_URL = ${BUILD_URL}consoleText"
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
