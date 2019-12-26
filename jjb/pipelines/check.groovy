// constansts
REGISTRY_IP = "pnexus.sytes.net"
REGISTRY_PORT = "5001"
LOGS_HOST = "pnexus.sytes.net"
LOGS_BASE_PATH = "/var/www/logs/jenkins_logs"
LOGS_BASE_URL = "http://pnexus.sytes.net:8082/jenkins_logs"

// pipeline flow variables
logs_url = ""
gerrit_pipeline = ""
top_jobs_to_run = []
top_jobs_code = [:]
test_configuration_names = []
inner_jobs_code = [:]
jobs_from_config = [:]
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
                  "deploy-platform-${name}"
                  [job: "deploy-platform-${name}",
                   parameters: [
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
                return 'status' in job_results[name]
              }
              if (job_results[name]['status'] != 'SUCCESS') {
                unstable("Deploy platform failed - skip deploy TF and tests for ${name}")
                return
              }

              try {
                top_job_number = job_results[name]['job'].getNumber()
                run_build(
                  "deploy-tf-${name}",
                  [job: "deploy-tf-${name}",
                   parameters: [
                    string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                    string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                    [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                  ]])
                test_jobs = [:]
                ['test-sanity', 'test-smoke'].each { test_name ->
                  test_jobs["${test_name} for deploy-tf-${name}"] = {
                    stage(test_name) {
                      // next variable must be taken again due to closure limitations for free variables
                      top_job_number = job_results[name]['job'].getNumber()
                      run_build(
                        "test_name-${name}",
                        [job: test_name,
                         parameters: [
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
                  top_job_number = job_results[name]['job'].getNumber()
                  println "Trying to collect logs and cleanup workers for ${name} job ${top_job_number}"
                  run_build(
                    "collect-logs-and-cleanup",
                    [job: "collect-logs-and-cleanup",
                     parameters: [
                      string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                      string(name: 'DEPLOY_PLATFORM_JOB_NAME', value: "deploy-platform-${name}"),
                      string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                      booleanParam(name: 'COLLECT_SANITY_LOGS', value: job_results["deploy-tf-${name}"]['status'] == 'SUCCESS'),
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
      echo "export PIPELINE_NAME=${JOB_NAME}" > global.env
      echo "export PIPELINE_BUILD_TAG=${BUILD_TAG}" >> global.env
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
      possible_top_jobs = ['test-lint', 'test-unit', 'build']
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
  println "Notify gerrit verified=${verified}, msg=${msg}, submit=${submit}"
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
    sh """#!/bin/bash -ex
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

def gerrit_build_started(){
  try {
    def msg = """Build Started ${BUILD_URL}"""
    notify_gerrit(msg)
  } catch (err) {
    print "Failed to provide vote to gerrit "
    msg = err.getMessage()
    if (msg != null) {
      print msg
    }
  }
}

def gerrit_vote(){
  try {    
    rc = currentBuild.result
    //TODO: include only items from config/projects.yaml (exclude fetch-sources, join deploy/sanity jobs)
    //TODO: evaluate all jobs statutes, exclude non-voting jobs and decide about final status 
    if (rc == 'SUCCESS') {
      verified = 1
      msg = "Build Succeeded (${gerrit_pipeline})\n"
    } else {
      verified = -1
      msg = "Build Failed (${gerrit_pipeline})\n"
    }
    for (result in job_results) {
      name = result.getKey()
      value = result.getValue()
      status = 'NOT RUN'
      if (value.containsKey('status'))
        status = value['status']
      }
      //TODO: check for non-voting job
      job_logs = "${logs_url}/${value['logs_dir']}"
      msg += "\n- ${name} ${job_logs} : ${status}"
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
  job_results[name] = ['logs_dir': params['job']]
  try {
    job_params_to_file(name)
    job = build(params)
    job_results[name]['job'] = job
    job_results[name]['status'] = job.getResult()
    println "Finished ${name} with SUCCSESS"
  } catch (err) {
    println "Failed ${name}"
    msg = err.getMessage()
    if (msg != null) {
      println msg
    }
    job_results[name]['status'] = 'FAILURE'
    throw(err)
  }
}
