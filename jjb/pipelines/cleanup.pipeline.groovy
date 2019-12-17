pipeline{
    agent any
    environment {
        PIPELINE_NAME = "check-pipeline"
    }
    stages{
        stage ('Cleanup AWS'){
            agent { label 'aws'}
            steps {
                withCredentials(
                    bindings:
                        [[$class: 'AmazonWebServicesCredentialsBinding',
                            credentialsId: 'aws-creds',
                            accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                            secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]){
                sh """
                    export DEBUG=true
                    $WORKSPACE/src/progmaticlab/tf-jenkins/infra/aws/cleanup_trash.sh
                """
                }
            }
        }
    }
}
