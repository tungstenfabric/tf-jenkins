pipeline{
  agent any
  triggers{
    cron('*/20 * * * *')
  }
  stages{
    stage('Parallel stage') {
      parallel {
        stage('Cleanup stalled AWS Workers') {
          agent { label 'aws'}
          steps {
          checkout([$class: 'GitSCM', branches: [[name: '*/master']],
            doGenerateSubmoduleConfigurations: false,
            extensions: [],
            submoduleCfg: [],
            extensions: [[$class: 'RelativeTargetDirectory', 
              relativeTargetDir: 'src/progmaticlab/tf-jenkins']],
            userRemoteConfigs: [[url: 'https://github.com/progmaticlab/tf-jenkins.git']]])
            withCredentials(
              bindings:
                [[$class: 'AmazonWebServicesCredentialsBinding',
                credentialsId: 'aws-creds',
                accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]){
              sh """
                export DEBUG=true
                export SLAVE="aws"
                $WORKSPACE/src/progmaticlab/tf-jenkins/infra/aws/cleanup_stalled_workers.sh
              """
            }
          }
        }
        stage('Cleanup stalled VEXX Workers') {
          agent { label 'vexxhost'}
          steps {
            checkout([$class: 'GitSCM', branches: [[name: '*/master']],
              doGenerateSubmoduleConfigurations: false,
              extensions: [],
              submoduleCfg: [],
              extensions: [[$class: 'RelativeTargetDirectory', 
                relativeTargetDir: 'src/progmaticlab/tf-jenkins']],
              userRemoteConfigs: [[url: 'https://github.com/progmaticlab/tf-jenkins.git']]])
            withCredentials(
              bindings:
                [string(credentialsId: 'VEXX_OS_USERNAME', variable: 'OS_USERNAME'),
                string(credentialsId: 'VEXX_OS_PROJECT_NAME', variable: 'OS_PROJECT_NAME'),
                string(credentialsId: 'VEXX_OS_PASSWORD', variable: 'OS_PASSWORD'),
                string(credentialsId: 'VEXX_OS_DOMAIN_NAME', variable: 'OS_USER_DOMAIN_NAME'),
                string(credentialsId: 'VEXX_OS_DOMAIN_NAME', variable: 'OS_PROJECT_DOMAIN_NAME'),
                string(credentialsId: 'VEXX_OS_AUTH_URL', variable: 'OS_AUTH_URL')]){
              sh """
                export SLAVE="vexxhost"
                export DEBUG=true
                $WORKSPACE/src/progmaticlab/tf-jenkins/infra/vexxhost/cleanup_stalled_workers.sh
              """
              }
          }
        }
      }
    }
  }
}
