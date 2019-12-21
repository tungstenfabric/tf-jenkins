def top_jobs_to_run = []
def top_jobs_code = [:]
def top_job_results = [:]
def test_configuration_names = []
def inner_jobs_code = [:]

pipeline {
  environment {
    REGISTRY_IP = "pnexus.sytes.net"
    REGISTRY_PORT = "5001"
    LOGS_HOST = "pnexus.sytes.net"
    LOGS_BASE_PATH = "/var/www/logs/jenkins_logs"
    LOGS_BASE_URL = "http://pnexus.sytes.net:8082/jenkins_logs"
  }
  parameters {
    choice(name: 'SLAVE', choices: ['vexxhost', 'aws'],
      description: 'Slave where all jobs will be run: vexxhost, aws')
    booleanParam(name: 'DO_BUILD', defaultValue: true,
      description: 'Run full build and use images later. Otherwise use nightly build.')
    booleanParam(name: 'DO_RUN_UT_LINT', defaultValue: true,
      description: 'Run UT and Lint jobs.')
    booleanParam(name: 'DO_CHECK_K8S_MANIFESTS', defaultValue: true,
      description: 'Run checks for k8s with manifests.')
    booleanParam(name: 'DO_CHECK_JUJU_K8S', defaultValue: false,
      description: 'Run checks for k8s with juju.')
    booleanParam(name: 'DO_CHECK_JUJU_OS', defaultValue: false,
      description: 'Run checks for OpenStack with juju.')
    booleanParam(name: 'DO_CHECK_ANSIBLE_OS', defaultValue: true,
      description: 'Run checks for OpenStack with ansible-deployer.')
    booleanParam(name: 'DO_CHECK_ANSIBLE_K8S', defaultValue: true,
      description: 'Run checks for Kubernetes with ansible-deployer.')
    booleanParam(name: 'DO_CHECK_HELM_K8S', defaultValue: false,
      description: 'Run checks for k8s with helm-deployer.')
    booleanParam(name: 'DO_CHECK_HELM_OS', defaultValue: false,
      description: 'Run checks for OpenStack with helm-deployer.')
  }
  options {
    timestamps()
    timeout(time: 4, unit: 'HOURS')
  }
  agent {
    label "${SLAVE}"
  }
  stages {
    stage('Pre-build') {
      steps {
        script {
          try {
            sh """
              echo "export PIPELINE_NAME=${JOB_NAME}" > global.env
              echo "export PIPELINE_BUILD_TAG=${BUILD_TAG}" >> global.env
            """

            // evvaluate logs params
            if (env.GERRIT_CHANGE_ID) {
              contrail_container_tag = GERRIT_CHANGE_NUMBER + '-' + GERRIT_PATCHSET_NUMBER
              hash = env.GERRIT_CHANGE_NUMBER.reverse().take(2).reverse()
              logs_path="${LOGS_BASE_PATH}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/pipeline_${BUILD_NUMBER}"
              logs_url="${LOGS_BASE_URL}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/pipeline_${BUILD_NUMBER}"
            } else {
              contrail_container_tag = 'dev'
              logs_path="${LOGS_BASE_PATH}/manual/pipeline_${BUILD_NUMBER}"
              logs_url="${LOGS_BASE_URL}/manual/pipeline_${BUILD_NUMBER}"
            }
            sh """
              echo "export LOGS_HOST=${LOGS_HOST}" >> global.env
              echo "export LOGS_PATH=${logs_path}" >> global.env
              echo "export LOGS_URL=${logs_url}" >> global.env
            """

            // store gerrit input if present. evaluate jobs 
            if (env.GERRIT_CHANGE_ID) {
              sh """
                echo "export GERRIT_CHANGE_ID=${env.GERRIT_CHANGE_ID}" >> global.env
                echo "export GERRIT_CHANGE_URL=${env.GERRIT_CHANGE_URL}" >> global.env
                echo "export GERRIT_BRANCH=${env.GERRIT_BRANCH}" >> global.env
                echo "export GERRIT_PROJECT=${env.GERRIT_PROJECT}" >> global.env
                echo "export GERRIT_CHANGE_NUMBER=${env.GERRIT_CHANGE_NUMBER}" >> global.env
                echo "export GERRIT_PATCHSET_NUMBER=${env.GERRIT_PATCHSET_NUMBER}" >> global.env
              """
            } else {
              if (params.DO_BUILD || params.DO_RUN_UT_LINT) {
                top_jobs_to_run += 'fetch-sources'
              }
              if (params.DO_RUN_UT_LINT) {
                top_jobs_to_run += 'test-unit'
                top_jobs_to_run += 'test-lint'
              }
              if (params.DO_BUILD) {
                top_jobs_to_run += 'build'
              }
              if (params.DO_CHECK_K8S_MANIFESTS) test_configuration_names += 'k8s_manifests'
              if (params.DO_CHECK_JUJU_K8S) test_configuration_names += 'juju_k8s'
              if (params.DO_CHECK_JUJU_OS) test_configuration_names += 'juju_os'
              if (params.DO_CHECK_ANSIBLE_OS) test_configuration_names += 'ansible_os'
              if (params.DO_CHECK_ANSIBLE_K8S) test_configuration_names += 'ansible_k8s'
              if (params.DO_CHECK_HELM_K8S) test_configuration_names += 'helm_k8s'
              if (params.DO_CHECK_HELM_OS) test_configuration_names += 'helm_os'
            }
            println 'Test configurations: ' + test_configuration_names

            // evaluate registry params
            if ('build' in top_jobs_to_run || 'test-lint' in top_jobs_to_run || 'test-unit' in top_jobs_to_run) {
              sh """
                echo "export REGISTRY_IP=${REGISTRY_IP}" >> global.env
                echo "export REGISTRY_PORT=${REGISTRY_PORT}" >> global.env
                echo "export CONTAINER_REGISTRY=${REGISTRY_IP}:${REGISTRY_PORT}" >> global.env
                echo "export CONTRAIL_CONTAINER_TAG=${contrail_container_tag}" >> global.env
              """
            }
          } catch (err) {
            println "Failed set environment ${err.getMessage()}"
            error(err.getMessage())
          }
        }
        archiveArtifacts artifacts: 'global.env'
      }
    }
    stage('Fetch') {
      steps {
        script {
          if ('fetch-sources' in top_jobs_to_run) {
            build job: 'fetch-sources',
              parameters: [
                string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"],
              ]
          }
        }
      }
    }
    stage('Check') {
      steps {
        script {
          ['test-unit', 'test-lint'].each {
            name -> if (name in top_jobs_to_run) {
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

          test_configuration_names.each {
            name -> top_jobs_code["Deploy platform for ${name}"] = {
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
                  error(err.getMessage())
                }
              }
            }
          }
          test_configuration_names.each {
            name -> inner_jobs_code["Deploy TF for ${name}"] = {
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
                  println "top_job_number = ${top_job_number}"
                  try {
                    build job: "deploy-tf-${name}",
                      parameters: [
                        string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                        string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                        [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                      ]
                    top_job_results[name]['status-tf'] = 'SUCCESS'
                  } catch (err) {
                    top_job_results[name]['status-tf'] = 'FAILURE'
                    println "Failed to run deploy TF deploy platform for ${name}"
                    println err.getMessage()
                    error(err.getMessage())
                  }
                  test_jobs = [:]
                  ['test-sanity', 'test-smoke'].each {
                    test_name -> test_jobs["${test_name} for deploy-tf-${name}"] = {
                      stage(test_name) {
                        // next variable must be taken again due to closure limitations for free variables
                        top_job_number = top_job_results[name]['build_number']
                        println "top_job_number(inner) = ${top_job_number}"
                        build job: test_name,
                          parameters: [
                            string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                            string(name: 'DEPLOY_PLATFORM_PROJECT', value: "deploy-platform-${name}"),
                            string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                            [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                          ]
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
                    println err.getMessage()
                  }
                }
              }
            }
          }

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

          parallel top_jobs_code
        }
      }
    }
  }
  post {
    always {
      sh "env|sort"
      sh "echo 'Destroy VMs'"
      withCredentials(
        bindings:
          [[$class: 'AmazonWebServicesCredentialsBinding',
              credentialsId: 'aws-creds',
              accessKeyVariable: 'AWS_ACCESS_KEY_ID',
              secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'],
          string(credentialsId: 'VEXX_OS_USERNAME', variable: 'OS_USERNAME'),
          string(credentialsId: 'VEXX_OS_PROJECT_NAME', variable: 'OS_PROJECT_NAME'),
          string(credentialsId: 'VEXX_OS_PASSWORD', variable: 'OS_PASSWORD'),
          string(credentialsId: 'VEXX_OS_DOMAIN_NAME', variable: 'OS_USER_DOMAIN_NAME'),
          string(credentialsId: 'VEXX_OS_DOMAIN_NAME', variable: 'OS_PROJECT_DOMAIN_NAME'),
          string(credentialsId: 'VEXX_OS_AUTH_URL', variable: 'OS_AUTH_URL')]) {
        sh """
          export DEBUG=true
          $WORKSPACE/src/progmaticlab/tf-jenkins/infra/${SLAVE}/cleanup_pipeline_workers.sh
        """
      }
    }
    failure {
      sh "echo 'archiveArtifacts'"
      sh "echo 'gerrit vote'"
    }
    success {
      sh "echo 'gerrit vote'"
      sh "echo publishArtifact"
    }
    cleanup {
      sh "echo 'remove trash'"
    }
  }
}
