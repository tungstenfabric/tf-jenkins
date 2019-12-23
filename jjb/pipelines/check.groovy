// constansts
REGISTRY_IP = "pnexus.sytes.net"
REGISTRY_PORT = "5001"
LOGS_HOST = "pnexus.sytes.net"
LOGS_BASE_PATH = "/var/www/logs/jenkins_logs"
LOGS_BASE_URL = "http://pnexus.sytes.net:8082/jenkins_logs"

// pipeline flow variables
logs_url = ""
top_jobs_to_run = []
top_jobs_code = [:]
top_job_results = [:]
test_configuration_names = []
inner_jobs_code = [:]

timestamps {
  try {
    timeout(time: 4, unit: 'HOURS') {
      node("${SLAVE}") {
        stage('Pre-build') {
          evaluate_env()
          archiveArtifacts artifacts: 'global.env'
        }
        println "Logs URL: ${logs_url}"
        println 'Top jobs to run: ' + top_jobs_to_run
        println 'Test configurations: ' + test_configuration_names

        if ('fetch-sources' in top_jobs_to_run) {
          stage('Fetch') {
            build job: 'fetch-sources',
              parameters: [
                string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"],
              ]
          }
        }

        // build independent jobs
        ['test-unit', 'test-lint'].each { name ->
          if (name in top_jobs_to_run) {
            top_jobs_code[name] = {
              stage(name) {
                build job: name,
                  parameters: [
                    string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                    [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                  ]
              }
            }
          }
        }

        // declaration of deploy platform parts
        test_configuration_names.each { name ->
          top_jobs_code["Deploy platform for ${name}"] = {
            stage("Deploy platform for ${name}") {
              println "Started deploy platform for ${name}"
              top_job_results[name] = [:]
              try {
                timeout(time: 60, unit: 'MINUTES') {
                  job = build job: "deploy-platform-${name}",
                    parameters: [
                      string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                      [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                    ]
                }
                top_job_results[name]['build_number'] = job.getNumber()
                top_job_results[name]['status'] = job.getResult()
                println "Finished deploy platform for ${name} with ${top_job_results[name]}"
              } catch (err) {
                println "Failed deploy platform for ${name}"
                top_job_results[name]['status'] = 'FAILURE'
                throw(err)
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
                return 'status' in top_job_results[name]
              }
              if (top_job_results[name]['status'] != 'SUCCESS') {
                unstable("Deploy platform failed - skip deploy TF and tests for ${name}")
                return
              }

              try {
                top_job_number = top_job_results[name]['build_number']
                try {
                  build job: "deploy-tf-${name}",
                    parameters: [
                      string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                      string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                      [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                    ]
                  top_job_results[name]['status-tf'] = 'SUCCESS'
                  println "Finished deploy TF for ${name} with SUCCESS"
                } catch (err) {
                  top_job_results[name]['status-tf'] = 'FAILURE'
                  println "Failed deploy TF for ${name}"
                  msg = err.getMessage()
                  if (msg != null) {
                    println msg
                  }
                  throw(err)
                }
                test_jobs = [:]
                ['test-sanity', 'test-smoke'].each { test_name ->
                  test_jobs["${test_name} for deploy-tf-${name}"] = {
                    stage(test_name) {
                      try {
                        // next variable must be taken again due to closure limitations for free variables
                        top_job_number = top_job_results[name]['build_number']
                        build job: test_name,
                          parameters: [
                            string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                            string(name: 'DEPLOY_PLATFORM_PROJECT', value: "deploy-platform-${name}"),
                            string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                            [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                          ]
                        println "${test_name} passed for ${name}"
                      } catch(err) {
                        println "${test_name} failed for ${name}"
                        throw(err)
                      }
                    }
                  }
                }
                parallel test_jobs
              } finally {
                top_job_number = top_job_results[name]['build_number']
                println "Trying to collect logs and cleanup workers for ${name} job ${top_job_number}"
                try {
                  stage('Collect logs and cleanup') {
                    build job: "collect-logs-and-cleanup",
                      parameters: [
                        string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                        string(name: 'DEPLOY_PLATFORM_JOB_NAME', value: "deploy-platform-${name}"),
                        string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                        booleanParam(name: 'COLLECT_SANITY_LOGS', value: top_job_results[name]['status-tf'] == 'SUCCESS'),
                        [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                      ]
                  }
                } catch(err) {
                  println "Failed to cleanup workers for ${name}"
                  msg = err.getMessage()
                  if (msg != null) {
                    println msg
                  }
                }
              }
            }
          }
        }

        // check if build is enabled
        if ('build' in top_jobs_to_run) {
          top_jobs_code['Build images for testing'] = {
            stage('build') {
              build job: 'build',
                parameters: [
                  string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                  [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                ]
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
      }
    }

    println "Logs URL: ${logs_url}"
    // add gerrit voting +1
  } catch(err) {
    msg = err.getMessage()
    if (err != null) {
      println "General pipeline error: ${msg}"
    }
    // add gerrit voting -1
    throw(err)
  } finally {
    println "Destroy VMs"
    build job: 'cleanup-pipeline-workers',
      parameters: [
        string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
        [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"],
      ]
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
      jobs = get_jobs(env.GERRIT_PROJECT)
      println "Evaluated jobs to run: ${jobs}"
      possible_top_jobs = ['test-lint', 'test-unit', 'build']
      for (item in jobs) {
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

def get_jobs(project) {
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
  jobs = [:]
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
        if (templates[template].get('check') && templates[template].check.get('jobs')) {
          for (job_item in templates[template].check.jobs) {
            add_job(jobs, job_item)
          }
        }
      }
    }
    if (project.get('check') && project.check.get('jobs')) {
      for (job_item in project.check.jobs) {
        add_job(jobs, job_item)
      }
    }
  }
  return jobs
}

def add_job(jobs, job_item) {
  if (job_item instanceof String) {
    jobs[job_item] = [:]
  } else {
    job = job_item.entrySet().iterator().next()
    jobs[job.getKey()] = job.getValue()
  }
}
