// constansts
REGISTRY_IP = "pnexus.sytes.net"
REGISTRY_PORT = "5001"
LOGS_HOST = "pnexus.sytes.net"
LOGS_BASE_PATH = "/var/www/logs/jenkins_logs"
LOGS_BASE_URL = "http://pnexus.sytes.net:8082/jenkins_logs"

// pipeline flow variables
// input pipeline - check, experimental, ... TODO: add nightly
gerrit_pipeline = ""
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

timestamps {
  timeout(time: 4, unit: 'HOURS') {
    node("${SLAVE}") {
      try {
        stage('Pre-build') {
          clone_self()
          evaluate_env()
          archiveArtifacts artifacts: 'global.env'
          println "Logs URL: ${logs_url}"
          println 'Top jobs to run: ' + top_jobs_to_run
          println 'Test configurations: ' + test_configuration_names
          gerrit_build_started()
        }

        if ('fetch-sources' in top_jobs_to_run) {
          stage('Fetch') {
            run_build(
              'fetch-sources',
              [job: 'fetch-sources',
                parameters: [
                string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
                string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"],
              ]])
          }
        }

        // build independent jobs
        ['test-unit', 'test-lint'].each { name ->
          if (name in top_jobs_to_run) {
            top_jobs_code[name] = {
              stage(name) {
                run_build(
                  name,
                  [job: name,
                   parameters: [
                    string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
                    string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                    [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                  ]])
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
                run_build(
                  "deploy-platform-${name}",
                  [job: "deploy-platform-${name}",
                   parameters: [
                    string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
                    string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                    [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                  ]])
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
                sleep 15
                return job_results["deploy-platform-${name}"].containsKey('result')
              }
              if (job_results["deploy-platform-${name}"]['result'] != 'SUCCESS') {
                unstable("Deploy platform failed - skip deploy TF and tests for ${name}")
                return
              }

              try {
                top_job_number = job_results["deploy-platform-${name}"]['number']
                run_build(
                  "deploy-tf-${name}",
                  [job: "deploy-tf-${name}",
                   parameters: [
                    string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
                    string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                    string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                    [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                  ]])
                def test_jobs = [:]
                get_test_job_names(name).each { test_name ->
                  test_jobs["${test_name} for deploy-tf-${name}"] = {
                    stage("${test_name}-${name}") {
                      // next variable must be taken again due to closure limitations for free variables
                      top_job_number = job_results["deploy-platform-${name}"]['number']
                      run_build(
                        "${test_name}-${name}",
                        [job: test_name,
                         parameters: [
                          string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
                          string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                          string(name: 'DEPLOY_PLATFORM_PROJECT', value: "deploy-platform-${name}"),
                          string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                          [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                        ]])
                    }
                  }
                }
                parallel test_jobs
              } finally {
                stage('Collect logs and cleanup') {
                  top_job_number = job_results["deploy-platform-${name}"]['number']
                  println "Trying to collect logs and cleanup workers for ${name} job ${top_job_number}"
                  run_build(
                    "collect-logs-and-cleanup",
                    [job: "collect-logs-and-cleanup",
                     parameters: [
                      string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
                      string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                      string(name: 'DEPLOY_PLATFORM_JOB_NAME', value: "deploy-platform-${name}"),
                      string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                      booleanParam(name: 'COLLECT_SANITY_LOGS', value: job_results["deploy-tf-${name}"]['result'] == 'SUCCESS'),
                      [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                    ]])
                }
              }
            }
          }
        }

        // check if build is enabled
        if ('build' in top_jobs_to_run) {
          top_jobs_code['Build images for testing'] = {
            stage('build') {
              run_build(
                'build',
                [job: 'build',
                 parameters: [
                  string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
                  string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                  [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                ]])
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
          run_build('cleanup-pipeline-workers',
            [job: 'cleanup-pipeline-workers',
             parameters: [
              string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
              string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
              [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"],
            ]])
        } catch(err){
        }

        // add gerrit voting +1/-1
        gerrit_vote()
      }
    }
  }
}


def evaluate_env() {
  try {
    sh """#!/bin/bash -e
      echo "export PIPELINE_BUILD_TAG=${BUILD_TAG}" > global.env
    """

    // evvaluate logs params
    if (env.GERRIT_CHANGE_ID) {
      contrail_container_tag = GERRIT_CHANGE_NUMBER + '-' + GERRIT_PATCHSET_NUMBER
      hash = env.GERRIT_CHANGE_NUMBER.reverse().take(2).reverse()
      logs_path = "${LOGS_BASE_PATH}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/pipeline_${BUILD_NUMBER}"
      logs_url = "${LOGS_BASE_URL}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/pipeline_${BUILD_NUMBER}"
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
    do_fetch = false
    if (env.GERRIT_CHANGE_ID) {
      sh """#!/bin/bash -e
        echo "export GERRIT_CHANGE_ID=${env.GERRIT_CHANGE_ID}" >> global.env
        echo "export GERRIT_CHANGE_URL=${env.GERRIT_CHANGE_URL}" >> global.env
        echo "export GERRIT_BRANCH=${env.GERRIT_BRANCH}" >> global.env
        echo "export GERRIT_PROJECT=${env.GERRIT_PROJECT}" >> global.env
        echo "export GERRIT_CHANGE_NUMBER=${env.GERRIT_CHANGE_NUMBER}" >> global.env
        echo "export GERRIT_PATCHSET_NUMBER=${env.GERRIT_PATCHSET_NUMBER}" >> global.env
      """
      gerrit_pipeline = 'check'
      if (env.GERRIT_EVENT_COMMENT_TEXT) {
        for (line in env.GERRIT_EVENT_COMMENT_TEXT.split('\n'))
        if (line =~ /^(check|recheck)/) {
          line_items = line.split()
          if (line_items.length > 1) {
            gerrit_pipeline = line_items[1]
          }
          break
        }
      }
      println "Pipeline to run: ${gerrit_pipeline}"
      get_jobs(env.GERRIT_PROJECT, gerrit_pipeline)
      println "Evaluated jobs to run: ${jobs_from_config}"
      def possible_top_jobs = ['test-lint', 'test-unit', 'build']
      for (item in jobs_from_config) {
        if (item.getKey() in possible_top_jobs) {
          top_jobs_to_run += item.getKey()
          do_fetch = true
        } else {
          test_configuration_names += item.getKey()
        }
      }
    } else {
      if (params.DO_RUN_UT_LINT) {
        top_jobs_to_run += 'test-unit'
        top_jobs_to_run += 'test-lint'
        do_fetch = true
      }
      if (params.DO_BUILD) {
        top_jobs_to_run += 'build'
        do_fetch = true
      }
      if (params.DO_CHECK_K8S_MANIFESTS) test_configuration_names += 'k8s_manifests'
      if (params.DO_CHECK_JUJU_K8S) test_configuration_names += 'juju_k8s'
      if (params.DO_CHECK_JUJU_OS) test_configuration_names += 'juju_os'
      if (params.DO_CHECK_ANSIBLE_K8S) test_configuration_names += 'ansible_k8s'
      if (params.DO_CHECK_ANSIBLE_OS) test_configuration_names += 'ansible_os'
      if (params.DO_CHECK_HELM_K8S) test_configuration_names += 'helm_k8s'
      if (params.DO_CHECK_HELM_OS) test_configuration_names += 'helm_os'
    }
    if (do_fetch) {
      top_jobs_to_run += 'fetch-sources'
    }

    // evaluate registry params
    if ('build' in top_jobs_to_run || 'test-lint' in top_jobs_to_run || 'test-unit' in top_jobs_to_run) {
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

def notify_gerrit(msg, verified=0, submit=false) {
  println "Notify gerrit verified=${verified}, submit=${submit}, msg=\n${msg}"
  withCredentials(
      bindings: [
        usernamePassword(credentialsId: 'gerrit-api',
        passwordVariable: 'GERRIT_API_PASSWORD',
        usernameVariable: 'GERRIT_API_USER')]) {
    opts = ""
    if (verified != null) {
      opts += " --labels VerifiedTF=${verified}"
    }
    if (submit) {
      opts += " --submit"
    }
    sh """
      ${WORKSPACE}/tf-jenkins/infra/gerrit/notify.py \
        --gerrit https://${GERRIT_HOST} \
        --user ${GERRIT_API_USER} \
        --password ${GERRIT_API_PASSWORD} \
        --review ${GERRIT_CHANGE_ID} \
        --branch ${GERRIT_BRANCH} \
        --message "${msg}" \
        ${opts}
    """
  }
}

def gerrit_build_started() {
  try {
    def msg = """Build Started (${gerrit_pipeline}) ${BUILD_URL}"""
    notify_gerrit(msg)
  } catch (err) {
    print "Failed to provide comment to gerrit "
    def msg = err.getMessage()
    if (msg != null) {
      print msg
    }
  }
}

def gerrit_vote() {
  try {
    def passed = true
    def results = [:]
    def msg = ''
    for (name in top_jobs_to_run) {
      def status = ''
      def job_result = job_results[name]
      if (!job_result) {
        status = 'NOT_BUILT'
        msg += "\n- ${name} : NOT_BUILT"
      } else {
        status = job_result['result']
        msg += "\n- " + get_gerrit_msg_for_job(name, status, job_result.get('duration'))
      }
      def voting = jobs_from_config.get(name, [:]).get('voting', true)
      if (!voting) {
        msg += ' (non-voting)'
      }
      if (voting && status != 'SUCCESS') {
        passed = false
      }
    }
    for (name in test_configuration_names) {
      def job_names = ["deploy-platform-${name}", "deploy-tf-${name}"]
      get_test_job_names(name).each{test_name -> job_names += "${test_name}-${name}"}
      def jobs_found = false
      def status = 'SUCCESS'
      def duration = 0
      for (job_name in job_names) {
        def job_result = job_results[job_name]
        if (!job_result) {
          status = 'FAILURE'
        } else {
          jobs_found = true
          if (status == 'SUCCESS' && job_result['result'] != 'SUCCESS') {
            // we can't provide exact job's status due to parallel test jobs
            status = 'FAILURE'
          }
          // TODO: calculate duration correctly
          // duration = max(0, {deploy-platform} - {build}) + {deploy-tf} + max({test-sanity}, {test-smoke})
          duration += job_result.get('duration', 0)
        }
      }
      if (!jobs_found) {
        status = 'NOT_BUILT'
        msg += "\n- ${name} : NOT_BUILT"
      } else {
        msg += "\n- " + get_gerrit_msg_for_job(name, status, duration)
      }
      def voting = jobs_from_config[name].get('voting', true)
      if (!voting) {
        msg += ' (non-voting)'
      }
      if (voting && status != 'SUCCESS') {
        passed = false
      }
    }

    def verified = 1
    if (passed) {
      msg = "Build Succeeded (${gerrit_pipeline})\n" + msg
    } else {
      msg = "Build Failed (${gerrit_pipeline})\n" + msg
      verified = -1
    }
    notify_gerrit(msg, verified)
  } catch (err) {
    print "Failed to provide vote to gerrit "
    msg = err.getMessage()
    if (msg != null) {
      print msg
    }
  }
}

def get_gerrit_msg_for_job(name, status, duration) {
  def duration_string = ''
  if (duration != null) {
    d = (int)(duration/1000)
    duration_string = String.format("in %dh %dm %ds", (int)(d/3600), (int)(d/60)%60, d%60)
  }
  return "${name} ${logs_url}/${name} : ${status} ${duration_string}"
}

def get_test_job_names(test_config_name) {
  def config = jobs_from_config.get(test_config_name)
  if (!config) {
    return ['test-sanity']
  }
  def job_names = []
  if (config.get('sanity', true)) {
    job_names += 'test-sanity'
  }
  if (config.get('smoke', false)) {
    job_names += 'test-sanity'
  }
  return job_names
}

def job_params_to_file(job_name) {
  if (!jobs_from_config.containsKey(job_name) || !jobs_from_config[job_name].containsKey('vars'))
    return

  env_file = "${job_name}.env"
  env_text = ""
  for (jvar in jobs_from_config[job_name]['vars']) {
    env_text += "export ${jvar.getKey()}='${jvar.getValue()}'\n"
  }
  writeFile(file: env_file, text: env_text)
  archiveArtifacts artifacts: "${env_file}"
}

def run_build(name, params) {
  def job_name = params['job']
  job_results[name] = [:]
  try {
    job_params_to_file(name)
    def job = build(params)
    job_results[name]['result'] = job.getResult()
    job_results[name]['number'] = job.getNumber()
    job_results[name]['duration'] = job.getDuration()
    println "Finished ${name} with SUCCESS"
  } catch (err) {
    println "Failed ${name}"
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
        def job = Jenkins.getInstanceOrNull().getItemByFullName(job_name).getBuildByNumber(build_num)
        job_results[name]['result'] = job.getResult()
        job_results[name]['number'] = job.getNumber()
        job_results[name]['duration'] = job.getDuration()
      }
    } catch(e) {
      println("Error in obtaining failed job result ${err.getMessage()}")
    }
    // re-throw error
    throw(err)
  }
}
