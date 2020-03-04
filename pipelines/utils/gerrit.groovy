// Gerrit utils

VERIFIED_SUCCESS_VALUES= [
  'check': 1,
  'gate': 2
]

VERIFIED_FAIL_VALUES= [
  'check': -1,
  'gate': -2
]

def _get_gerrit_msg_for_job(name, status, duration) {
  def duration_string = _get_duration_string(duration)
  return "${name} ${logs_url}/${name} : ${status} ${duration_string}"
}

def _get_duration_string(duration) {
  if (duration == null) {
    return ""
  }
  d = (int)(duration/1000)
  return String.format("in %dh %dm %ds", (int)(d/3600), (int)(d/60)%60, d%60)
}

def _notify_gerrit(msg, verified=0, submit=false) {
  if (!env.GERRIT_HOST) {
    // looks like it's a nightly pipeline
    return
  }
  println("Notify gerrit verified=${verified}, submit=${submit}, msg=\n${msg}")
  withCredentials(
    bindings: [
      usernamePassword(credentialsId: env.GERRIT_HOST,
      passwordVariable: 'GERRIT_API_PASSWORD',
      usernameVariable: 'GERRIT_API_USER')]) {
    opts = ""

    //label_name = 'VerifiedTF'
    // temporary hack to not vote for review.opencontrail.org
    label_name = 'Verified'
    if (env.GERRIT_HOST == 'review.opencontrail.org')
      label_name = 'VerifiedTF'

    if (verified != null) {
      opts += " --labels ${label_name}=${verified}"
    }
    if (submit) {
      opts += " --submit"
    }
    url = resolve_gerrit_url()
    sh """
      ${WORKSPACE}/tf-jenkins/infra/gerrit/notify.py \
        --gerrit ${url} \
        --user ${GERRIT_API_USER} \
        --password ${GERRIT_API_PASSWORD} \
        --review ${GERRIT_CHANGE_ID} \
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

    url = resolve_gerrit_url()
    output = ""
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
      println(output)
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

def resolve_gerrit_url() {
  def url = "http://${env.GERRIT_HOST}/"
  while (true) {
    def getr = new URL(url).openConnection()
    getr.setFollowRedirects(false)
    code = (int)(getr.getResponseCode() / 100)
    if (code != 3)
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
    print "Failed to provide comment to gerrit "
    def msg = err.getMessage()
    if (msg != null) {
      print msg
    }
  }
}

def gerrit_vote(pre_build_done, full_duration) {
  return
  try {
    def passed = pre_build_done
    def results = [:]
    def msg = ''
    for (name in top_jobs_to_run) {
      def status = ''
      def job_result = job_results[name]
      if (!job_result) {
        status = 'NOT_BUILT'
        msg += "\n- ${name} : NOT_BUILT"
      } else {
        status = job_result['result']
        msg += "\n- " + _get_gerrit_msg_for_job(name, status, job_result.get('duration'))
      }
      def voting = jobs_from_config.get(name, [:]).get('voting', true)
      if (!voting) {
        msg += ' (non-voting)'
      }
      if (voting && status != 'SUCCESS') {
        passed = false
      }
    }
    for (name in test_configuration_names) {
      def job_names = ["deploy-platform-${name}", "deploy-tf-${name}"]
      get_test_job_names(name).each {test_name -> job_names += "${test_name}-${name}"}
      def jobs_found = false
      def status = 'SUCCESS'
      for (job_name in job_names) {
        def job_result = job_results[job_name]
        if (!job_result) {
          status = 'FAILURE'
        } else {
          jobs_found = true
          if (status == 'SUCCESS' && job_result['result'] != 'SUCCESS') {
            // we can't provide exact job's status due to parallel test jobs
            status = 'FAILURE'
          }
        }
      }
      // Calculate duration of test configuration = {deploy-platform} + {deploy-tf} + {max([test-unit, test-sanity])}
      def duration = 0
      for (job_name in ["deploy-platform-${name}", "deploy-tf-${name}"]) {
        job_result = job_results[job_name]
        if (job_result) {
          duration += job_result.get('duration', 0)
        }
      }
      def max_test_duration = 0
      for (test_name in get_test_job_names(name)) {
        job_result = job_results["${test_name}-${name}"]
        if (job_result && job_result.get('duration', 0) > max_test_duration) {
          max_test_duration = job_result['duration']
        }
      }
      duration += max_test_duration

      if (!jobs_found) {
        status = 'NOT_BUILT'
        msg += "\n- ${name} : NOT_BUILT"
      } else {
        msg += "\n- " + _get_gerrit_msg_for_job(name, status, duration)
      }
      def voting = jobs_from_config[name].get('voting', true)
      if (!voting) {
        msg += ' (non-voting)'
      }
      if (voting && status != 'SUCCESS') {
        passed = false
      }
    }

    def duration_string = _get_duration_string(full_duration)
    def verified = VERIFIED_SUCCESS_VALUES[env.GERRIT_PIPELINE]
    if (passed) {
      msg = "Jenkins Build Succeeded (${env.GERRIT_PIPELINE}) ${duration_string}\n" + msg
    } else {
      msg = "Jenkins Build Failed (${env.GERRIT_PIPELINE}) ${duration_string}\n" + msg
      verified = VERIFIED_FAIL_VALUES[env.GERRIT_PIPELINE]
    }
    _notify_gerrit(msg, verified)
    return verified
  } catch (err) {
    print "Failed to provide vote to gerrit "
    msg = err.getMessage()
    if (msg != null) {
      print msg
    }
  }
  return 0
}

// TODO: to remove
def get_test_job_names(test_config_name) {
  def config = jobs_from_config.get(test_config_name)
  if (!config) {
    return ['test-sanity']
  }
  def job_names = []
  if (config.get('sanity', true)) {
    job_names += 'test-sanity'
  }
  if (config.get('smoke', false)) {
    job_names += 'test-smoke'
  }
  return job_names
}

return this
