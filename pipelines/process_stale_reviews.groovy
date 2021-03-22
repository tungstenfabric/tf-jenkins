// constants
constants = null
// gerrit utils
gerrit_utils = null

timestamps {
  timeout(time: 10, unit: 'MINUTES') {
    node('vexxhost') {
      if (env.GERRIT_PIPELINE != 'submit' && env.GERRIT_PIPELINE != 'gate')
        throw new Exception("ERROR: This pipeline only for gate/submit triggers!")

      clone_self()
      constants = load("${WORKSPACE}/src/baukin/tf-jenkins/pipelines/constants.groovy")
      gerrit_utils = load("${WORKSPACE}/src/baukin/tf-jenkins/pipelines/utils/gerrit.groovy")
      gerrit_utils.process_stale_reviews(env.GERRIT_PIPELINE)
    }
  }
}

def clone_self() {
  checkout([
    $class: 'GitSCM',
    branches: [[name: "*/master"]],
    doGenerateSubmoduleConfigurations: false,
    submoduleCfg: [],
    userRemoteConfigs: [[url: 'https://github.com/baukin/tf-jenkins.git']],
    extensions: [
      [$class: 'CleanBeforeCheckout'],
      [$class: 'CloneOption', depth: 1],
      [$class: 'RelativeTargetDirectory', relativeTargetDir: 'src/baukin/tf-jenkins']
    ]
  ])
}
