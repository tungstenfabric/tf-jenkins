//def test_configurations = ['k8s_manifests', 'os_ansible', 'k8s_juju', 'k8s_helm', 'os_helm']
def test_configurations = ['k8s_manifests', 'os_ansible', 'k8s_juju']
def top_jobs = [:]
def top_job_results = [:]
def inner_jobs = [:]

pipeline {
  environment {
    REGISTRY_IP = "pnexus.sytes.net"
    REGISTRY_PORT = "5001"
    DO_BUILD = '1'
  }
  parameters {
    choice(name: 'SLAVE', choices: ['vexxhost', 'aws'], description: '')
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
          if (env.GERRIT_CHANGE_NUMBER && env.GERRIT_PATCHSET_NUMBER) {
            CONTRAIL_CONTAINER_TAG = GERRIT_CHANGE_NUMBER + '-' + GERRIT_PATCHSET_NUMBER
          } else {
            CONTRAIL_CONTAINER_TAG = 'dev'
          }
          sh """
            echo "export PIPELINE_BUILD_TAG=${BUILD_TAG}" > global.env
            echo "export REGISTRY_IP=${REGISTRY_IP}" >> global.env
            echo "export REGISTRY_PORT=${REGISTRY_PORT}" >> global.env
            echo "export CONTAINER_REGISTRY=${REGISTRY_IP}:${REGISTRY_PORT}" >> global.env
            echo "export CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG}" >> global.env
            echo "export GERRIT_CHANGE_ID=${env.GERRIT_CHANGE_ID}" >> global.env
            echo "export GERRIT_CHANGE_URL=${env.GERRIT_CHANGE_URL}" >> global.env
            echo "export GERRIT_BRANCH=${env.GERRIT_BRANCH}" >> global.env
          """
        }
        archiveArtifacts artifacts: 'global.env'
      }
    }
    stage('Fetch') {
      steps {
        script {
          build job: 'fetch-sources',
            parameters: [
              string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
              [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"],
            ]
        }
      }
    }
    stage('Check') {
      steps {
        script {
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
                try {
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
                        export ENV_FILE="$WORKSPACE/stackrc.deploy-platform-${name}.env"
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

          if (DO_BUILD == '1') {
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
