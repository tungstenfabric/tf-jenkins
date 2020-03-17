// Gerrit utils

VERIFIED_SUCCESS_VALUES = ['check': 1, 'gate': 2]
VERIFIED_FAIL_VALUES = ['check': -1, 'gate': -2]

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
    def msg = """Jenkins Build Started (${env.GERRIT_PIPELINE}) ${BUILD_URL}"""
    _notify_gerrit(msg)
  } catch (err) {
    println("Failed to provide comment to gerrit")
    def msg = err.getMessage()
    if (msg != null) {
      println(msg)
    }
  }
}

def gerrit_vote(pre_build_done, streams, job_set, job_results, full_duration) {
  try {
    if (!pre_build_done) {
      msg = "Jenkins general failure (${env.GERRIT_PIPELINE})\nPlease check pipeline logs:\n"
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
      msg = "Jenkins Build Succeeded (${env.GERRIT_PIPELINE}) ${duration_string}\n" + msg
    } else {
      msg = "Jenkins Build ${stopping_cause} (${env.GERRIT_PIPELINE}) ${duration_string}\n" + msg
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

def _notify_gerrit(msg, verified=0, submit=false) {
  // TODO: remove this hack when gating will be implemented
  if (env.GERRIT_PIPELINE == 'gate')
    return

  if (!env.GERRIT_HOST) {
    if (env.GERRIT_PIPELINE == 'nightly') {
      emailext body: msg, subject: '[TF-JENKINS] Nightly build report', to: '$DEFAULT_RECIPIENTS'
    }
    return
  }
  println("Notify gerrit verified=${verified}, submit=${submit}, msg=\n${msg}")
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
    // TODO: send comment by sha or patchset num
    sh """
      ${WORKSPACE}/tf-jenkins/infra/gerrit/notify.py \
        --gerrit ${url} \
        --user ${GERRIT_API_USER} \
        --password ${GERRIT_API_PASSWORD} \
        --review ${GERRIT_CHANGE_ID} \
        --patchset ${GERRIT_PATCHSET_NUMBER} \
        --branch ${GERRIT_BRANCH} \
        --message "${msg}" \
        ${opts}
    """
  }
}

def _has_approvals(approvals) {
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
        ${WORKSPACE}/tf-jenkins/infra/gerrit/check_approvals.py \
          --debug \
          --gerrit ${url} \
          --user ${GERRIT_API_USER} \
          --password ${GERRIT_API_PASSWORD} \
          --review ${GERRIT_CHANGE_ID} \
          --branch ${GERRIT_BRANCH} \
          --approvals '${approvals}' 
      """).trim()
      println(output)
      return true
    } catch (err) {
      println("Exeption in check_approvals.py")
      def msg = err.getMessage()
      if (msg != null) {
        println(msg)
      }
      return false
    }
  }
}

def has_gate_approvals() {
  return _has_approvals('VerifiedTF:recommended:1,Code-Review:approved,Approved:approved')
}

def has_gate_submits() {
  return _has_approvals('VerifiedTF:approved,Code-Review:approved,Approved:approved')  
}

return this
