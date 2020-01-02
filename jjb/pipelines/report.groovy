pipeline{
  agent any
  triggers{
    cron('15 6 * * *')
  }
  stages{
    stage('Parallel stage') {
      parallel {
        stage('Build aws usage report') {
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
                $WORKSPACE/src/progmaticlab/tf-jenkins/infra/aws/report.sh
              """
              stash allowEmpty: true, name: "aws", excludes: "src/**"
            }
          }
        }
        stage('Build Vexxhost usage report') {
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
                $WORKSPACE/src/progmaticlab/tf-jenkins/infra/vexxhost/report.sh
              """
              stash allowEmpty: true, name: "vexxhost", excludes: "src/**"
            }
          }
        }
      }
    }
  }
  post {
    // ToDo: send report if exist
    always {
      unstash "aws"
      unstash "vexxhost"
      emailext body: 'test', subject: '[TF-JENKINS] Daily report', to: '$DEFAULT_RECIPIENTS'
    }
  }
}
