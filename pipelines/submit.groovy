// gerrit utils
gerrit = null

timestamps {
  timeout(time: 10, unit: 'MINUTES') {
    node('master') {
      if (env.GERRIT_PIPELINE != 'submit')
        throw new Exception("ERROR: This pipeline only for submit trigger!")

      clone_self()
      gerrit = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/utils/gerrit.groovy")
      println("Verified value to report on success: ${gerrit.VERIFIED_SUCCESS_VALUES[env.GERRIT_PIPELINE]}")
      if (gerrit.has_gate_submits()) {
        gerrit.notify_gerrit("Submit for merge", null, true)
      } else {
        println("There is no submit labels.. skip submit to merge")
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
