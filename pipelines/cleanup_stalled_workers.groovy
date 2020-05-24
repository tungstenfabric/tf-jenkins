pipeline {
  agent any
  triggers {
    cron('*/20 * * * *')
  }
  options {
    timeout(time: 10, unit: 'MINUTES') 
  }
  stages {
    stage('Parallel stage') {
      parallel {
        stage('Cleanup stalled AWS Workers') {
          agent { label 'aws'}
          steps {
            clone_self()
            withCredentials(
              bindings:
                [[$class: 'AmazonWebServicesCredentialsBinding',
                credentialsId: 'aws-creds',
                accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
              sh """
                export SLAVE="aws"
                $WORKSPACE/src/tungstenfabric/tf-jenkins/infra/aws/cleanup_stalled_workers.sh
              """
            }
          }
        }
        stage('Cleanup stalled VEXX Workers') {
          agent { label 'vexxhost'}
          steps {
            clone_self()
            withCredentials(
              bindings:
                [string(credentialsId: 'VEXX_OS_USERNAME', variable: 'OS_USERNAME'),
                string(credentialsId: 'VEXX_OS_PROJECT_NAME', variable: 'OS_PROJECT_NAME'),
                string(credentialsId: 'VEXX_OS_PASSWORD', variable: 'OS_PASSWORD'),
                string(credentialsId: 'VEXX_OS_DOMAIN_NAME', variable: 'OS_USER_DOMAIN_NAME'),
                string(credentialsId: 'VEXX_OS_DOMAIN_NAME', variable: 'OS_PROJECT_DOMAIN_NAME'),
                string(credentialsId: 'VEXX_OS_AUTH_URL', variable: 'OS_AUTH_URL')]) {
              sh """
                export SLAVE="vexxhost"
                $WORKSPACE/src/tungstenfabric/tf-jenkins/infra/vexxhost/cleanup_stalled_workers.sh
              """
            }            
          }
        }
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
    userRemoteConfigs: [[url: 'https://github.com/tungstenfabric/tf-jenkins.git']],
    extensions: [
      [$class: 'CleanBeforeCheckout'],
      [$class: 'CloneOption', depth: 1],
      [$class: 'RelativeTargetDirectory', relativeTargetDir: 'src/tungstenfabric/tf-jenkins']
    ]
  ])
}
