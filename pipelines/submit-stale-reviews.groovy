// constansts
TIMEOUT_HOURS = 4

// gerrit utils
def gerrit

timestamps {
  timeout(time: TIMEOUT_HOURS, unit: 'HOURS') {
    node("${SLAVE}") {
      checkout([
        $class: 'GitSCM',
        branches: [[name: "*/master"]],
        doGenerateSubmoduleConfigurations: false,
        submoduleCfg: [],
        userRemoteConfigs: [[url: 'https://github.com/progmaticlab/tf-jenkins.git']],
        extensions: [
          [$class: 'CleanBeforeCheckout'],
          [$class: 'CloneOption', depth: 1],
          [$class: 'RelativeTargetDirectory', relativeTargetDir: 'tf-jenkins']
        ]
      ])
      gerrit = load("${WORKSPACE}/tf-jenkins/pipelines/utils/gerrit.groovy")
      gerrit.submit_stale_reviews()
    }
  }
}
