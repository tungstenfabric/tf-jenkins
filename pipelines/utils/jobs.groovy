// jobs utils

def run(def jobs, def streams, def gate_utils, def gerrit_utils) {
  if (env.GERRIT_PIPELINE == 'gate')
    run_gating(jobs, streams, gate_utils, gerrit_utils)
  else
    run_jobs(jobs, streams)
}

def run_gating(def jobs, def streams, def gate_utils, def gerrit_utils) {
  while (true) {
    def base_build_id = gate_utils.save_base_builds()
    try {
      if (gate_utils.is_concurrent_project()) {
        // Run immediately if projest can be run concurrently
        println("DEBUG: Concurrent project - run jobs")
        run_jobs(jobs, streams)
      } else {
        // Wait for the same project pipeline is finishes
        println("DEBUG: Serial run - wait until finishes previous pipeline")
        gate_utils.wait_until_project_pipeline()
        println("DEBUG: Project in serial list - run jobs")
        run_jobs(jobs, streams)
      }
    } catch(Exception err) {
      println("DEBUG: Something fails ${err}")
      if (!gate_utils.check_build_is_not_failed(env.BUILD_ID.toInteger())){
        // If build has been failed - throw exection
        println("DEBUG: Build has been realy failed")
        throw err
      } else {
        println("DEBUG: Build was not failed - try again")
      }
    } finally {
      // Finish the loop if pipeline was aborted
      def result = gate_utils.get_build_result_by_id(env.BUILD_ID.toInteger())
      if (result == "ABORTED")
        break

      if (!base_build_id) {
        // we do not have base build - Just finish the job
        println("DEBUG: We do NOT have base pipeline. Finishing...")
        break
      }

      println("DEBUG: We found base pipeline ${base_build_id} and are waiting for base pipeline")
      gate_utils.wait_pipeline_finished(base_build_id)
      println("DEBUG: Base pipeline has been finished")
      if (gate_utils.check_build_is_not_failed(base_build_id)) {
        // Finish the pipeline if base build finished successfully
        // else try to find new base build
        println("DEBUG: Base pipeline has been verified")
        break
      } else {
        println("DEBUG: Base pipeline has not been verified. Run build again...")
      }

      // treat pipeline as restarted and cleanup vars in global.env
      // Delete BASE_BUILD_ID_LIST from global.env
      gate_utils.cleanup_globalenv_vars()
      // reset_patchset_info to start state
      gerrit_utils.resolve_patchsets()
    }
  }
}

def run_jobs(def job_set, def streams) {
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
            _run_job(job_set, name, streams)
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

def get_jobs_result_for_gerrit(job_set, job_results) {
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
  return results
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
    for (def dep in deps) {
      def dep_name = dep instanceof String ? dep : dep.keySet().toArray()[0]
      result_map[dep_name] = job_results.containsKey(dep_name) ? job_results[dep_name].get('result') : null
    }
    println("JOB ${name}: waiting for dependecy ${result_map}")
    results = result_map.values()
    if (post_hook) {
      // wait while 'null' is still in results
      println("JOB ${name}: waiting for all = ${!results.contains(null)}")
      return !results.contains(null)
    }
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

def _job_params_to_file(def job_set, def name, def streams, def env_file) {
  if (!job_set.containsKey(name))
    return

  def job_name = job_set[name].get('job-name', name)
  def env_text = ""
  def vars = [:]
  if (job_set[name].containsKey('stream')) {
    stream = streams.get(job_set[name]['stream'])
    if (stream && stream.containsKey('vars')) {
      vars += stream['vars']
    }
  }
  if (job_set[name].containsKey('vars'))
    vars += job_set[name]['vars']
  def vars_keys = vars.keySet() as List
  if (vars_keys.size() == 0) {
    println("JOB ${name}: vars empty. do not store vars file.")
    return
  }
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
  def stream = job_set[name].get('stream')
  println("JOB ${name}: deps: ${deps}")
  def raw_data = []
  // simple loop to avoid java.io.NotSerializableException: org.codehaus.groovy.util.ArrayIterator
  for (def i = 0; i < deps.size(); ++i) {
    def dep = deps[i]
    def dep_name = dep instanceof String ? dep : dep.keySet().toArray()[0]
    def dep_keys = dep instanceof String ? [] : dep[dep_name].get('inherit-keys', [])
    def dep_stream = job_set[dep_name].get('stream')
    def dep_job_name = job_set[dep_name].get('job-name', dep_name)
    def dep_job_rnd = job_results[dep_name]['job-rnd']
    dir("${WORKSPACE}") {
      def files = findFiles(glob: "${dep_job_name}-${dep_job_rnd}/*.env")
      println("JOB ${name}: files found = ${files.size()}")
      for (def j = 0; j < files.size(); ++j) {
        println("JOB ${name}: file #${j} with path ${files[j].getPath()}")
        def data = readFile(files[j].getPath()).split('\n')
        if (stream == null || dep_stream == null || stream != dep_stream) {
          // simple loop to avoid java.io.NotSerializableException: org.codehaus.groovy.util.ArrayIterator
          // https://issues.jenkins-ci.org/browse/JENKINS-47730
          def filtered_data = []
          for (def k = 0; k < data.size(); ++k)
            if (data[k] && data[k].split('=')[0].split(' ')[-1] in dep_keys)
              filtered_data += data[k]
          data = filtered_data
        }
        if (files[j].getName().startsWith("deps."))
          raw_data.addAll(0, data)
        else
          raw_data.addAll(data)
      }
    }
  }
  def lines = []
  for (def i = 0; i < raw_data.size(); ++i) {
    def line = raw_data[i]
    if (line.size() > 0 && !lines.contains(line))
      lines += line
  }
  if (lines.size() == 0) {
    println("JOB ${name}: content of deps file is empty")
    return
  }
  println("JOB ${name}: deps_env_file: ${deps_env_file}")
  writeFile(file: deps_env_file, text: lines.join('\n') + '\n')
  archiveArtifacts(artifacts: deps_env_file)
}

// this method uses regexp search that is no serializable - thus apply NonCPS
@NonCPS
def _get_job_number_from_exception(def run_err) {
  def causes = run_err.getCauses()
  if (causes == null || causes.size() == 0)
    return null
  def cause_msg = causes[0].getShortDescription()
  def build_num_matcher = cause_msg =~ /#\d+/
  if (build_num_matcher.find())
    return ((build_num_matcher[0] =~ /\d+/)[0]).toInteger()
  return null
}

def _run_job(def job_set, def name, def streams) {
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
    _job_params_to_file(job_set, name, streams, vars_env_file)
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
    job_results[name]['result'] = job.getResult().toString()
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
        job_results[name]['result'] = job.getResult().toString()
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
    println("JOB ${name}: Collected artifacts:")
    sh("ls -la ${target_dir} || /bin/true") // folder can be absent
    _save_job_output(name, job_name, stream, job_number)
  }
  // re-throw error
  if (run_err != null)
    throw run_err
}

def _save_job_output(name, job_name, stream, job_number) {
  withCredentials(bindings: [sshUserPrivateKey(credentialsId: 'logs_host', keyFileVariable: 'LOGS_HOST_SSH_KEY', usernameVariable: 'LOGS_HOST_USERNAME')]) {
    ssh_cmd = "ssh -i ${LOGS_HOST_SSH_KEY} -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
    sh """#!/bin/bash
      curl -s ${JENKINS_URL}job/${job_name}/${job_number}/consoleText > output-${name}.log
      ${ssh_cmd} ${LOGS_HOST_USERNAME}@${LOGS_HOST} "mkdir -p ${logs_path}/${stream}/"
      rsync -a -e "${ssh_cmd}" output-${name}.log ${LOGS_HOST_USERNAME}@${LOGS_HOST}:${logs_path}/${stream}/
    """
  }
}

return this
