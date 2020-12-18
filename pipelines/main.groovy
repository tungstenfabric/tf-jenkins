// pipeline flow variables
// base url for all jobs
logs_url = ""
logs_path = ""

rnd = new Random()
gerrit_url = null

constants = null
// gerrit utils
gerrit_utils = null
// config utils
config_utils = null
// jobs utils
jobs_utils = null

// local constants
TIMEOUT_HOURS = 6
if (env.GERRIT_PIPELINE == 'nightly') {
  TIMEOUT_HOURS = 9
}

timestamps {
  timeout(time: TIMEOUT_HOURS, unit: 'HOURS') {
    node("${SLAVE}") {
      if (!env.GERRIT_CHANGE_ID && env.GERRIT_PIPELINE != 'nightly') {
        println("Manual run is forbidden")
        return
      }

      stage('init') {
        try {
          cleanWs(disableDeferredWipeout: true, notFailBuild: true, deleteDirs: true)
          clone_self()

          gerrit_utils = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/utils/gerrit.groovy")
          if (env.GERRIT_CHANGE_ID) {
            // resolve gerrit_url for further usage
            gerrit_url = gerrit_utils.resolve_gerrit_url()
            // resolve patcchsets
            gerrit_utils.resolve_patchsets()
            // apply patchsets file onto tf-jenkins repo to get latest changes from review if exist
            sh """#!/bin/bash -e
              export GERRIT_URL=${gerrit_url}
              ./src/tungstenfabric/tf-jenkins/infra/gerrit/apply_patchsets.sh ./src tungstenfabric/tf-jenkins ./patchsets-info.json
            """
            // always reload utils (if tf-jenkins in patchset's list)
            gerrit_utils = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/utils/gerrit.groovy")
          }

          constansts = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/constants.groovy")
          config_utils = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/utils/config.groovy")
          jobs_utils = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/utils/jobs.groovy")
          gate_utils = load("${WORKSPACE}/src/tungstenfabric/tf-jenkins/pipelines/utils/gate.groovy")
        } catch (err) {
          println(err.getMessage())
          verified = gerrit_utils.gerrit_vote(false, null, null, null, null, err.getMessage())
          throw(err)
        }
      }
      if (env.GERRIT_PIPELINE == 'gate' && !gerrit_utils.has_gate_approvals()) {
        println("There is no gate approvals. skip gate")
        currentBuild.description = "Not ready to gate"
        currentBuild.result = 'UNSTABLE'
        return
      }

      jobs_utils.main(gate_utils, gerrit_utils, config_utils)
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
