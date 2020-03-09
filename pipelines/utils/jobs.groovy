// jobs utils

def run_jobs(def job_set) {
  def jobs_code = [:]
  job_set.keySet().each { name ->
    job_results[name] = [:]
    job_results[name]['job-rnd'] = "${rnd.nextInt(99999)}"
    jobs_code[name] = {
      stage(name) {
        try {
          def result = _wait_for_dependencies(job_set, name)
          if (result) {
            // TODO: add optional timeout from config - timeout(time: 60, unit: 'MINUTES')
            _run_job(job_set, name)
          } else {
            job_results[name]['number'] = -1
            job_results[name]['duration'] = 0
            job_results[name]['result'] = 'NOT_BUILT'
          }
        } catch (err) {
          println("JOB ${name}: error in job!!!")
          println("JOB ${name}: Err - ${err}")
          println("JOB ${name}: Message - ${err.getMessage()}")
          println("JOB ${name}: Cause - ${err.getCause()}")
          println("JOB ${name}: Stacktrace - ${err.getStackTrace()}")
          throw(err)
        }
      }
    }
  }

  // run jobs in parallel
  if (jobs_code.size() > 0)
    parallel(jobs_code)
}

def _wait_for_dependencies(job_set, name) {
  def deps = job_set[name].get('depends-on')
  if (deps == null || deps.size() == 0)
    return true
  println("JOB ${name}: waiting for dependecies")
  def post_hook = job_set[name].get('type') == 'stream-post-hook'
  def overall_result = true
  waitUntil(initialRecurrencePeriod: 15000) {
    def result_map = [:]
    for (def i = 0; i < deps.size(); ++i) {
      dep_name = deps[i]
      result_map[dep_name] = job_results.containsKey(dep_name) ? job_results[dep_name].get('result') : null
    }
    println("JOB ${name}: waiting for dependecy ${result_map}")
    results = result_map.values()
    if (post_hook) {
      // wait while 'null' is still in results
      println("JOB ${name}: waiting for all = ${!results.contains(null)}")
      return !results.contains(null)
    }

    println("DEBUG: ......")
    println(results)
    println('FAILURE' in results || 'UNSTABLE' in results || 'NOT_BUILT'in results || 'ABORTED' in results)
    println('FAILURE' in results)
    println('SUCCESS' in results)

    // stop waiting if someone failed
    if ('FAILURE' in results || 'UNSTABLE' in results || 'NOT_BUILT'in results || 'ABORTED' in results) {
      overall_result = false
      return true
    }
    // continue waiting if someone still is not ready
    if (null in results) {
      println("JOB ${name}: fails were not found, unfinished jobs are still present")
      return false
    }
    // here only SUCCESS is in the results - stop waiting
    return true
  }
  println("JOB ${name}: wait finished. overall result = ${overall_result}")
  return overall_result
}

def _job_params_to_file(job_set, name, env_file) {
  if (!job_set.containsKey(name) || !job_set[name].containsKey('vars'))
    return

  def job_name = job_set[name].get('job-name', name)
  def env_text = ""
  def vars = job_set[name]['vars']
  def vars_keys = vars.keySet() as List
  // simple for-loop to avoid non-Serializable exception
  for (def i = 0; i < vars_keys.size(); ++i) {
    env_text += "export ${vars_keys[i]}='${vars[vars_keys[i]]}'\n"
  }
  writeFile(file: env_file, text: env_text)
  archiveArtifacts(artifacts: env_file)
}

def _collect_dependent_env_files(job_set, name, deps_env_file) {
  if (!job_set.containsKey(name) || !job_set[name].containsKey('depends-on'))
    return
  def deps = job_set[name].get('depends-on')
  if (deps == null || deps.size() == 0)
    return
  println("JOB ${name}: deps: ${deps}")
  def raw_data = []
  // simple for-loop to avoid non-Serializable exception
  for (def i = 0; i < deps.size(); ++i) {
    def job_name = job_set[deps[i]].get('job-name', deps[i])
    def job_rnd = job_results[deps[i]]['job-rnd']
    dir("${WORKSPACE}") {
      def files = findFiles(glob: "${job_name}-${job_rnd}/*.env")
      for (def j = 0; j < files.size(); ++j) {
        data = readFile(files[j].getPath())
        raw_data.addAll(data.split('\n'))
      }
    }
  }
  def lines = []
  for (def i = 0; i < raw_data.size(); ++i) {
    def line = raw_data[i]
    if (line.size() > 0 && !lines.contains(line))
      lines += line
  }
  if (lines.size() == 0)
    return
  println("JOB ${name}: deps_env_file: ${deps_env_file}")
  writeFile(file: deps_env_file, text: lines.join('\n') + '\n')
  archiveArtifacts(artifacts: deps_env_file)
}

// this method uses regexp search that is no serializable - thus apply NonCPS
@NonCPS
def _get_job_number_from_exception(err) {
  def causes = err.getCauses()
  if (causes == null || causes.size() == 0)
    return null
  def cause_msg = causes[0].getShortDescription()
  def build_num_matcher = cause_msg =~ /#\d+/
  if (build_num_matcher.find())
    return ((build_num_matcher[0] =~ /\d+/)[0]).toInteger()
  return null
}

def _run_job(job_set, name) {
  println("JOB ${name}: entering run_job")
  // final cleanup job is not in config
  def job_name = job_set[name].get('job-name', name)
  def stream = job_set[name].get('stream', name)
  def job_rnd = job_results[name]['job-rnd']
  def vars_env_file = "vars.${job_name}.${job_rnd}.env"
  def deps_env_file = "deps.${job_name}.${job_rnd}.env"
  def job_number = null
  def run_err = null
  try {
    _job_params_to_file(job_set, name, vars_env_file)
    _collect_dependent_env_files(job_set, name, deps_env_file)
    def params = [
      string(name: 'STREAM', value: stream),
      string(name: 'JOB_RND', value: job_rnd),
      string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
      string(name: 'PIPELINE_NUMBER', value: "${BUILD_NUMBER}"),
      [$class: 'LabelParameterValue', name: 'NODE_NAME', label: "${NODE_NAME}"]]
    println("JOB ${name}: Starting job: ${job_name}  rnd: #${job_rnd}")
    def job = build(job: job_name, parameters: params)
    job_number = job.getNumber()
    job_results[name]['number'] = job_number
    job_results[name]['duration'] = job.getDuration()
    job_results[name]['result'] = job.getResult()
    println("JOB ${name}: Finished with SUCCESS")
  } catch (err) {
    run_err = err
    job_results[name]['result'] = 'FAILURE'
    println("JOB ${name}: Failed")
    def msg = err.getMessage()
    if (msg != null) {
      println("JOB ${name}: err msg: ${msg}")
    }
    // get build num from exception and find job to get duration and result
    try {
      job_number = _get_job_number_from_exception(run_err)
      if (job_number) {
        def job = Jenkins.getInstanceOrNull().getItemByFullName(job_name).getBuildByNumber(job_number)
        job_results[name]['number'] = job_number
        job_results[name]['duration'] = job.getDuration()
        job_results[name]['result'] = job.getResult()
      }
    } catch(e) {
      println("JOB ${name}: Error in obtaining failed job result ${e.getMessage()}")
    }
  }
  if (job_number != null) {
    target_dir = "${job_name}-${job_rnd}"
    copyArtifacts(
      filter: '*.env',
      excludes: "global.env,${vars_env_file}",
      optional: true,
      fingerprintArtifacts: true,
      projectName: job_name,
      selector: specific("${job_number}"),
      target: target_dir)
  }
  println("JOB ${name}: Collected artifacts:")
  sh("ls -la ${target_dir} || /bin/true") // folder can be absent
  // re-throw error
  if (run_err != null)
    throw run_err
}

return this
