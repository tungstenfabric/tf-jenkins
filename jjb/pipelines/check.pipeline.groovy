def test_configurations = []
def top_jobs = [:]
def top_job_results = [:]
def inner_jobs = [:]

pipeline {
  environment {
    REGISTRY_IP = "pnexus.sytes.net"
    REGISTRY_PORT = "5001"
    ARCHIVE_HOST = "pnexus.sytes.net"
    LOGS_FILE_PATH_BASE = "/var/www/logs/jenkins_logs/"
    SANITY_LOGS_PATH = "/home/centos/src/tungstenfabric/tf-test/contrail-sanity/contrail-test-runs/"

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
    booleanParam(name: 'DO_CHECK_K8S_JUJU', defaultValue: true,
      description: 'Run checks for k8s with juju.')
    booleanParam(name: 'DO_CHECK_OS_ANSIBLE', defaultValue: true,
      description: 'Run checks for OpenStack with ansible-deployer.')
    booleanParam(name: 'DO_CHECK_K8S_HELM', defaultValue: false,
      description: 'Run checks for k8s with helm-deployer.')
    booleanParam(name: 'DO_CHECK_OS_HELM', defaultValue: false,
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
          if (params.DO_CHECK_K8S_MANIFESTS) test_configurations += 'k8s_manifests'
          if (params.DO_CHECK_K8S_JUJU) test_configurations += 'k8s_juju'
          if (params.DO_CHECK_OS_ANSIBLE) test_configurations += 'os_ansible'
          if (params.DO_CHECK_K8S_HELM) test_configurations += 'k8s_helm'
          if (params.DO_CHECK_OS_HELM) test_configurations += 'os_helm'
          println 'Test configurations: ' + test_configurations
          test_configurations
          if (env.GERRIT_CHANGE_NUMBER && env.GERRIT_PATCHSET_NUMBER) {
            CONTRAIL_CONTAINER_TAG = GERRIT_CHANGE_NUMBER + '-' + GERRIT_PATCHSET_NUMBER
          } else {
            CONTRAIL_CONTAINER_TAG = 'master-nightly'
          }
          sh """
            echo "export PIPELINE_BUILD_TAG=${BUILD_TAG}" > global.env
            echo "export REGISTRY_IP=${REGISTRY_IP}" >> global.env
            echo "export REGISTRY_PORT=${REGISTRY_PORT}" >> global.env
            echo "export ARCHIVE_HOST=${ARCHIVE_HOST}" >> global.env
            echo "export SANITY_LOGS_PATH=${SANITY_LOGS_PATH}" >> global.env
            echo "export CONTAINER_REGISTRY=${REGISTRY_IP}:${REGISTRY_PORT}" >> global.env
            echo "export CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG}" >> global.env
          """
          if (env.GERRIT_CHANGE_ID) {
            sh """
              echo "export GERRIT_CHANGE_ID=${env.GERRIT_CHANGE_ID}" >> global.env
              echo "export GERRIT_CHANGE_URL=${env.GERRIT_CHANGE_URL}" >> global.env
              echo "export GERRIT_BRANCH=${env.GERRIT_BRANCH}" >> global.env
              echo "export GERRIT_PROJECT=${env.GERRIT_PROJECT}" >> global.env
              echo "export GERRIT_CHANGE_NUMBER=${env.GERRIT_CHANGE_NUMBER}" >> global.env
              echo "export GERRIT_PATCHSET_NUMBER=${env.GERRIT_PATCHSET_NUMBER}" >> global.env
              echo "export LOGS_FILE_PATH=${LOGS_FILE_PATH_BASE}/gerrit/${GERRIT_CHANGE_NUMBER: -2}/${GERRIT_CHANGE_NUMBER}/${GERRIT_PATCHSET_NUMBER}/" >> global.env
            """
          } else {
            sh """
              echo "export LOGS_FILE_PATH=${LOGS_FILE_PATH_BASE}/manual/" >> global.env
            """
          }
        }
        archiveArtifacts artifacts: 'global.env'
      }
    }
    stage('Fetch') {
      steps {
        script {
          if (params.DO_BUILD || params.DO_RUN_UT_LINT) {
            build job: 'fetch-sources',
              parameters: [
                string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"],
              ]
          } else {
            println "Build and UT&Lint jobs are switched off. Skipping fetch job."
          }
        }
      }
    }
    stage('Check') {
      steps {
        script {
          if (params.DO_RUN_UT_LINT) {
            top_jobs['test-unit'] = {
              stage('test-unit') {
                build job: 'test-unit',
                  parameters: [
                    string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                    [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                  ]
              }
            }
            top_jobs['test-lint'] = {
              stage('test-lint') {
                build job: 'test-lint',
                  parameters: [
                    string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                    [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                  ]
              }
            }
          }

          test_configurations.each {
            name -> top_jobs["Deploy platform for ${name}"] = {
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
          test_configurations.each {
            name -> inner_jobs["Deploy TF for ${name}"] = {
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
                  } catch (err) {
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
                  println "Trying to cleanup workers for ${name} job ${top_job_number}"
                  try {
                    copyArtifacts filter: "stackrc.deploy-platform-${name}.env",
                      fingerprintArtifacts: true,
                      projectName: "deploy-platform-${name}",
                      selector: specific("${top_job_number}")
                    withCredentials(
                      bindings:
                        [[$class: 'AmazonWebServicesCredentialsBinding',
                          credentialsId: 'aws-creds',
                          accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                          secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'],
                        sshUserPrivateKey(credentialsId: "archive_credentials", keyFileVariable: 'ARCHIVE_SSH_KEY',usernameVariable: 'ARCHIVE_USERNAME'),
                        sshUserPrivateKey(credentialsId: "worker", keyFileVariable: "WORKER_SSH_KEY"),
                        string(credentialsId: 'VEXX_OS_USERNAME', variable: 'OS_USERNAME'),
                        string(credentialsId: 'VEXX_OS_PROJECT_NAME', variable: 'OS_PROJECT_NAME'),
                        string(credentialsId: 'VEXX_OS_PASSWORD', variable: 'OS_PASSWORD'),
                        string(credentialsId: 'VEXX_OS_DOMAIN_NAME', variable: 'OS_USER_DOMAIN_NAME'),
                        string(credentialsId: 'VEXX_OS_DOMAIN_NAME', variable: 'OS_PROJECT_DOMAIN_NAME'),
                        string(credentialsId: 'VEXX_OS_AUTH_URL', variable: 'OS_AUTH_URL')]) {
                      sh """
                        export ENV_FILE="$WORKSPACE/stackrc.deploy-platform-${name}.env"
                        export CONF_PLATFORM="${name}"
                        export BUILD_TAG=${BUILD_TAG}
                        export DEBUG=true
                        if [[  -n "${GERRIT_CHANGE_ID}" ]]; then
                          export LOGS_FILE_PATH=${LOGS_FILE_PATH_BASE}/gerrit/${GERRIT_CHANGE_NUMBER: -2}/${GERRIT_CHANGE_NUMBER}/${GERRIT_PATCHSET_NUMBER}/
                        else
                          export LOGS_FILE_PATH=${LOGS_FILE_PATH_BASE}/manual/
                        fi
                        export SANITY_LOGS_PATH=${SANITY_LOGS_PATH}
                        "$WORKSPACE/src/progmaticlab/tf-jenkins/jobs/devstack/${name}/collect_logs.sh" || /bin/true
                        "$WORKSPACE/src/progmaticlab/tf-jenkins/infra/${SLAVE}/remove_workers.sh"
                      """
                    }
                  } catch(err) {
                    println "Failed to cleanup workers for ${name}"
                    println err.getMessage()
                  }
                }
              }
            }
          }

          if (params.DO_BUILD) {
            top_jobs['build-and-test'] = {
              stage('build') {
                build job: 'build',
                  parameters: [
                    string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                    [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                  ]
                parallel inner_jobs
              }
            }
          } else {
            top_jobs['just-test'] = {
              parallel inner_jobs
            }
          }

          parallel top_jobs
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
