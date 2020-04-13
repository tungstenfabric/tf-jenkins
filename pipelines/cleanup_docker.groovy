pipeline{
  agent any
  triggers{
    cron('* 21 * * *')
  }
  options {
    timeout(time: 10, unit: 'MINUTES') 
  }
  stages{
    stage('Cleanup docker on aws') {
      agent { label 'aws'}
      steps {
        sh '''
          docker container prune -f
          docker rmi $(docker images -f "dangling=true" -q) || /bin/true
          images=$(docker images --format '{{.Repository}}:{{.Tag}}' | \
              grep -v -F -x -e 'pnexus.sytes.net:5002/tf-developer-sandbox:stable' \
                        -e 'pnexus.sytes.net:5001/tf-developer-sandbox:stable' \
                        -e 'pnexus.sytes.net:5002/tf-developer-sandbox:stable-r1912' \
                        -e 'tf-developer-sandbox-stable:latest' || /bin/true )
          if [[ -n "$images" ]]; then
            for image in $images; do
              docker rmi $image || /bin/true
            done
          fi
        '''
        }
      }
    stage('Cleanup docker on vexx') {
      agent { label 'vexxhost'}
      steps {
        sh '''
          docker container prune -f
          docker rmi $(docker images -f "dangling=true" -q) || /bin/true
          images=$(docker images --format '{{.Repository}}:{{.Tag}}' | \
          grep -v -F -x -e 'pnexus.sytes.net:5002/tf-developer-sandbox:stable' \
                        -e 'pnexus.sytes.net:5001/tf-developer-sandbox:stable' \
                        -e 'pnexus.sytes.net:5002/tf-developer-sandbox:stable-r1912' \
                        -e 'tf-developer-sandbox-stable:latest' || /bin/true )
          if [[ -n "$images" ]]; then
            for image in $images; do
              docker rmi $image || /bin/true
            done
          fi
        '''
      }
    }
  }
}
