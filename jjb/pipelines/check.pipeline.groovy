def SLAVE = 'aws'

//def test_configurations = ['k8s_helm', 'k8s_manifests', 'k8s_juju', 'os_helm', 'os_ansible']
def test_configurations = ['k8s_manifests', 'os_ansible']
def top_jobs = [:]
def top_job_results = [:]
def inner_jobs = [:]

pipeline {
  environment {
    CONTAINER_REGISTRY = "pnexus.sytes.net:5001"
    PATCHSET_ID = "12345/1"
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
          sh """
            echo "CONTAINER_REGISTRY=${CONTAINER_REGISTRY}" > global.env
            echo "PATCHSET_ID=${PATCHSET_ID}" >> global.env
            echo "PIPELINE_BUILD_TAG=${BUILD_TAG}" >> global.env
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
                }
                top_job_number = top_job_results[name]['build_number']

                try {
                  build job: "deploy-tf-${name}",
                    parameters: [
                      string(name: 'PIPELINE_BUILD_NUMBER', value: "${BUILD_NUMBER}"),
                      string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                      [$class: 'LabelParameterValue', name: 'SLAVE', label: "${SLAVE}"]
                    ]
                } catch (err) {
                  println "Failed to run deploy TF deploy platform for ${name} "
                  println err.getMessage()
                  error(err.getMessage())
                }
                test_jobs = [:]
                ['test-sanity', 'test-smoke'].each {
                  test_name -> test_jobs["${test_name} for deploy-tf-${name}"] = {
                    stage(test_name) {
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
                println "Finished deploy TF and test for ${name} with ${top_job_results[name]}"
              }
            }
          }

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
            secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
        sh "$WORKSPACE/src/progmaticlab/tf-jenkins/infra/aws/remove_workers.sh"
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
