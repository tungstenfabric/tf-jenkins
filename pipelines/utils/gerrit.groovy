// Gerrit utils

VERIFIED_SUCCESS_VALUES = ['check': 1, 'gate': 2, 'nightly': 1]
VERIFIED_FAIL_VALUES = ['check': -1, 'gate': -2, 'nightly': -1]

def resolve_gerrit_url() {
  def url = "http://${env.GERRIT_HOST}/"
  while (true) {
    def getr = new URL(url).openConnection()
    getr.setFollowRedirects(false)
    if (((int)(getr.getResponseCode() / 100)) != 3)
      break
    url = getr.getHeaderField("Location")
  }
  println("INFO: resolved gerrit URL is ${url}")
  return url
}

def gerrit_build_started() {
  try {
    def msg = """TF CI Build Started (${env.GERRIT_PIPELINE}) ${BUILD_URL}"""
    _notify_gerrit(msg)
  } catch (err) {
    println("Failed to provide comment to gerrit")
    def msg = err.getMessage()
    if (msg != null) {
      println(msg)
    }
  }
}

def publish_results(pre_build_done, streams, job_set, job_results, full_duration, err_msg=null) {
  try {
    if (!pre_build_done) {
      msg = "TF CI general failure (${env.GERRIT_PIPELINE})\n\n"
      if (err_msg)
        msg += "${err_msg}\n\n"
      msg += "Please check pipeline logs:\n"
      msg += "${BUILD_URL}\n${logs_url}\n"
      _notify_gerrit(msg, VERIFIED_FAIL_VALUES[env.GERRIT_PIPELINE])
      return VERIFIED_FAIL_VALUES[env.GERRIT_PIPELINE]
    }

    def results = [:]
    for (name in job_set.keySet()) {
      // do not include post job into report
      if (job_set[name].get('type') == 'stream-post-hook')
        continue
      def stream = job_set[name].get('stream', name)
      def job_result = job_results.get(name)
      def result = job_result != null ? job_result.get('result', 'NOT_BUILT') : 'NOT_BUILT'
      def duration = job_result != null ? job_result.get('duration', 0) : 0
      if (!results.containsKey(stream)) {
        results[stream] = ['results': [result], 'duration': duration]
      } else {
        results[stream]['results'] += result
        results[stream]['duration'] += duration
      }
    }

    def passed = true
    def msg = ''
    def stopping_cause = 'Failed'
    for (stream in results.keySet()) {
      println("Evaluated results for ${stream} = ${results[stream]}")
      def result = _get_stream_result(results[stream]['results'])

      // Log stream result
      if (streams.containsKey(stream)) {
        vars = streams[stream][vars]
        if (vars.containsKey('MONITORING_DEPLOY_TARGET') &&
            vars.containsKey('MONITORING_DEPLOYER') &&
            vars.containsKey('MONITORING_ORCHESTRATOR')) {

              step([$class: 'Fluentd', tag: 'pipeline', json: """{
                "pipeline": "${currentBuild.projectName}",
                "deployer": "${vars['MONITORING_DEPLOYER']}",
                "orchestrator": "${vars['MONITORING_ORCHESTRATOR']}",
                "status" : "${result}",
                "gerrit": "${env.GERRIT_PIPELINE}",
                "target": "${vars['MONITORING_DEPLOY_TARGET']}"
                }"""])
        }
      }

      if (result == 'ABORTED') {
        stopping_cause = 'Aborted'
      }
      if (result == 'NOT_BUILT') {
        msg += "\n- ${stream} : NOT_BUILT"
      } else {
        msg += "\n- " + _get_gerrit_msg_for_job(stream, result, results[stream]['duration'])
      }
      def voting = true
      if (streams.containsKey(stream) && streams[stream].containsKey('voting')) {
        voting = streams[stream]['voting']
      } else if (jobs.containsKey(stream) && jobs[stream].containsKey('voting')) {
        voting = jobs[stream]['voting']
      }
      if (!voting) {
        msg += ' (non-voting)'
      }
      if (voting && result != 'SUCCESS') {
        passed = false
      }
    }

    def duration_string = _get_duration_string(full_duration)
    def verified = VERIFIED_SUCCESS_VALUES[env.GERRIT_PIPELINE]
    if (passed) {
      msg = "TF CI Build Succeeded (${env.GERRIT_PIPELINE}) ${duration_string}\n" + msg
    } else {
      msg = "TF CI Build ${stopping_cause} (${env.GERRIT_PIPELINE}) ${duration_string}\n" + msg
      verified = VERIFIED_FAIL_VALUES[env.GERRIT_PIPELINE]
    }
    _notify_gerrit(msg, verified)
    return verified
  } catch (err) {
    println("Failed to provide vote to gerrit")
    msg = err.getMessage()
    if (msg != null)
      println("Message - ${msg}")
    println("Stacktrace - ${err.getStackTrace()}")
  }
  return 0
}

def _get_stream_result(def results) {
  // There are 5 status available: NOT_BUILT, ABORTED, FAILURE, UNSTABLE, SUCCESS
  if ('FAILURE' in results || 'UNSTABLE' in results)
    return 'FAILURE'
  if ('ABORTED' in results)
    return 'ABORTED'
  if ('NOT_BUILT' in results && 'SUCCESS' in results)
    return 'ABORTED'
  return results[0]
}

def _get_gerrit_msg_for_job(stream, status, duration) {
  def duration_string = _get_duration_string(duration)
  return "${stream} ${logs_url}/${stream} : ${status} ${duration_string}"
}

def _get_duration_string(duration) {
  if (duration == null) {
    return ""
  }
  def d = (int)(duration/1000)
  return String.format("in %dh %dm %ds", (int)(d/3600), (int)(d/60)%60, d%60)
}

def _notify_gerrit(msg, verified=0, submit=false, change_id=null, branch=null, patchset_number=null) {
  println("Notify gerrit verified=${verified}, submit=${submit}, msg=\n${msg}")
  if (!env.GERRIT_HOST) {
    if (env.GERRIT_PIPELINE == 'nightly') {
      // println('Temporarily disabled')
      emailext body: msg, subject: '[TF-JENKINS] Nightly build report', to: '$DEFAULT_RECIPIENTS'
    }
    return
  }
  withCredentials(
    bindings: [
      usernamePassword(credentialsId: env.GERRIT_HOST,
      passwordVariable: 'GERRIT_API_PASSWORD',
      usernameVariable: 'GERRIT_API_USER')]) {
    def opts = ""

    //label_name = 'VerifiedTF'
    // temporary hack to not vote for review.opencontrail.org
    def label_name = 'Verified'
    if (env.GERRIT_HOST == 'review.opencontrail.org')
      label_name = 'VerifiedTF'

    if (verified != null) {
      opts += " --labels ${label_name}=${verified}"
    }
    if (submit) {
      opts += " --submit"
    }
    def url = resolve_gerrit_url()
    if (!change_id)
      change_id = env.GERRIT_CHANGE_ID
    if (!branch)
      branch = env.GERRIT_BRANCH
    if (!patchset_number)
      patchset_number = env.GERRIT_PATCHSET_NUMBER

    // TODO: send comment by sha or patchset num
    sh """
      ${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/gerrit/notify.py \
        --gerrit ${url} \
        --user ${GERRIT_API_USER} \
        --password ${GERRIT_API_PASSWORD} \
        --review ${change_id} \
        --patchset ${patchset_number} \
        --branch ${branch} \
        --message "${msg}" \
        ${opts}
    """
  }
}

def _has_approvals(strategy) {
  if (!env.GERRIT_HOST) {
    // looks like it's a nightly pipeline
    return false
  }
  withCredentials(
    bindings: [
      usernamePassword(credentialsId: env.GERRIT_HOST,
      passwordVariable: 'GERRIT_API_PASSWORD',
      usernameVariable: 'GERRIT_API_USER')]) {

    //label_name = 'VerifiedTF'
    // temporary hack to not vote for review.opencontrail.org
    // label_name = 'Verified'
    // if (env.GERRIT_HOST == 'review.opencontrail.org')
    //   label_name = 'VerifiedTF'

    def url = resolve_gerrit_url()
    def output = ""
    try {
      output = sh(returnStdout: true, script: """
        ${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/gerrit/check_approvals.py \
          --strategy ${strategy} \
          --gerrit ${url} \
          --user ${GERRIT_API_USER} \
          --password ${GERRIT_API_PASSWORD} \
          --review ${GERRIT_CHANGE_ID} \
          --branch ${GERRIT_BRANCH}
      """).trim()
      println(output)
      return true
    } catch (err) {
      println("check_approvals.py returns non-zero code. It means there is no approvals for now.")
      def msg = err.getMessage()
      if (msg != null) {
        println(msg)
      }
      return false
    }
  }
}

def resolve_patchsets() {
  sh """
    ${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/gerrit/resolve_patchsets.py \
      --gerrit ${gerrit_url} \
      --review ${GERRIT_CHANGE_ID} \
      --branch ${GERRIT_BRANCH} \
      --changed_files \
      --output ${WORKSPACE}/patchsets-info.json
  """
  archiveArtifacts(artifacts: 'patchsets-info.json')
}

def submit_stale_reviews() {
  if (!env.GERRIT_HOST) {
    return
  }
  withCredentials(
    bindings: [
      usernamePassword(credentialsId: env.GERRIT_HOST,
      passwordVariable: 'GERRIT_API_PASSWORD',
      usernameVariable: 'GERRIT_API_USER')]) {

    def url = resolve_gerrit_url()
    sh """
      ${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/gerrit/submit_stale_reviews.py \
        --gerrit ${url} \
        --user ${GERRIT_API_USER} \
        --password ${GERRIT_API_PASSWORD}
    """
  }
}

def has_gate_approvals() {
  def result = _has_approvals('gate')
  println("INFO: has_gate_approvals = ${result}")
  return result
}

def has_gate_submits() {
  def result = _has_approvals('submit')
  println("INFO: has_submit_approvals = ${result}")
  // TODO: remove return false and uncomment real result when we will be ready for this
  return false
  //return result
}

// block for termination utils

def terminate_runs_by_review_number() {
  // terminates pipeline for same review for previous patchset number
  def check = { action ->
    gerrit_change_number = action.getParameter("GERRIT_CHANGE_NUMBER")
    if (gerrit_change_number) {
      change_num = gerrit_change_number.value.toInteger()
      patchset_num = action.getParameter("GERRIT_PATCHSET_NUMBER").value.toInteger()
      if (env.GERRIT_CHANGE_NUMBER.toInteger() == change_num && env.GERRIT_PATCHSET_NUMBER.toInteger() > patchset_num)
        return true
    }
    return false
  }

  terminated = _check_and_stop_builds(check)
  for (params in terminated) {
    _notify_terminated(params)
  }
}

def terminate_runs_by_depends_on_recursive(def change_id) {
  // recursive terminating
  println('Search for dependent builds')
  def terminated = _terminate_runs_by_depends_on(change_id)
  for (params in terminated) {
    _notify_terminated(params)
    terminate_runs_by_depends_on_recursive(params['change_id'])
  }
}

def _terminate_runs_by_depends_on(def change_id) {
  // terminates builds that have change_id in Depends-On:
  // returns terminated build's properties
  def check = { action ->
    def gerrit_change_commit_message = action.getParameter("GERRIT_CHANGE_COMMIT_MESSAGE")
    if (gerrit_change_commit_message) {
      // decodeBase64 return byte array
      def commit_message = new String(gerrit_change_commit_message.value.decodeBase64())
      def commit_dependencies = _get_dependencies_for_commit(commit_message)
      if (commit_dependencies.contains(change_id))
        return true
    }
    return false
  }

  return _check_and_stop_builds(check)
}

def _check_and_stop_builds(def check_func) {
  def terminated = []
  def builds = Jenkins.getInstanceOrNull().getItemByFullName(env.JOB_NAME).getBuilds()
  for (def build in builds) {
    if (!build || !build.getResult().equals(null))
      continue
    def action = build.allActions.find { it in hudson.model.ParametersAction }
    if (!action)
      continue

    if (!check_func(action))
      continue

    terminated.add([
      'patchset_number': action.getParameter("GERRIT_PATCHSET_NUMBER").value.toInteger(),
      'change_id': action.getParameter("GERRIT_CHANGE_ID").value,
      'branch': action.getParameter("GERRIT_BRANCH").value
    ])

    build.doStop()
    println("Build ${build} has been aborted due to new patchset has been created for parent")
  }
  return terminated
}

def _notify_terminated(def params) {
  try {
    def msg = """Run has been aborted due to new parent check ${env.GERRIT_CHANGE_ID} has been started."""
    _notify_gerrit(msg, 0, false, params['change_id'], params['branch'], params['patchset_number'])
  } catch (err) {
    println("Failed to provide comment to gerrit")
    def msg = err.getMessage()
    if (msg != null) {
      println(msg)
    }
  }
}

def _get_dependencies_for_commit(commit_message) {
  def deps = []
  try {
    for (line in commit_message.split('\n')) {
      if (line.toLowerCase().startsWith('depends-on')) {
        deps.add(line.split(':')[1].trim())
      }
    }
  } catch(err) {
    println('WARNING! Unable to parse dependency string')
    def msg = err.getMessage()
    if (msg != null) {
      println(msg)
    }
  }
  return deps
}

return this
