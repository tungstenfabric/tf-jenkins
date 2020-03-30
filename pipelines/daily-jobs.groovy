pipeline{
  agent any
  triggers{
    cron('15 6 * * *')
  }
  environment {
    INSTANCES_LIST = ""
  }
  options {
    timeout(time: 10, unit: 'MINUTES') 
  }
  stages{
    stage('Parallel stage') {
      parallel {
        stage('Build aws usage report') {
          agent { label 'aws'}
          steps {
            cleanWs()
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
                export SLAVE="aws"
                $WORKSPACE/src/progmaticlab/tf-jenkins/infra/aws/report.sh
              """
              stash allowEmpty: true, name: "aws", excludes: "src/**"
            }
          }
        }
        stage('Docker cleanup') {
          steps{
            sh '''
            docker system prune -a --filter "until=48h" -f || true
            '''
          }
        }
        stage('Build Vexxhost usage report') {
          agent { label 'vexxhost'}
          steps {
            cleanWs()
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
                $WORKSPACE/src/progmaticlab/tf-jenkins/infra/vexxhost/report.sh
              """
              stash allowEmpty: true, name: "vexxhost", excludes: "src/**"
            }
          }
        }
        stage('Docker cleanup') {
          steps{
            sh '''
            docker system prune -a --filter "until=48h" -f || true
            '''
          }
        }
      }
    }
    stage('Build common usage report') {
      steps {
        cleanWs()
        unstash "aws"
        unstash "vexxhost"
        sh '''
        if [[ -f "$WORKSPACE/vexxhost.report.txt" ]]; then
          echo "VEXX instances alive more than 3 days:" >> report.txt
          cat $WORKSPACE/vexxhost.report.txt >> report.txt
        fi
        if [[ -f "$WORKSPACE/aws.report.txt" ]]; then
          echo "AWS instances alive more than 3 days:" >> report.txt
          cat $WORKSPACE/aws.report.txt >> report.txt
        fi
        '''
        script {
          if (fileExists('report.txt')) {
            def report = readFile 'report.txt'
            emailext body: report, subject: '[TF-JENKINS] Resource report', to: '$DEFAULT_RECIPIENTS'
          }
        }
      }
    }
  }
}
