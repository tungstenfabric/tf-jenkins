// gerrit utils
def gerrit

timestamps {
  timeout(time: 10, unit: 'MINUTES') {
    node('vexxhost') {
      if (env.GERRIT_PIPELINE != 'submit')
        throw new Exception("ERROR: This pipeline only for submit trigger!")

      clone_self()
      gerrit = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/utils/gerrit.groovy")
      gerrit.submit_stale_reviews()
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
