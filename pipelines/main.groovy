// constansts
TIMEOUT_HOURS = 4
REGISTRY_IP = "pnexus.sytes.net"
REGISTRY_PORT = "5001"
LOGS_HOST = "pnexus.sytes.net"
LOGS_BASE_PATH = "/var/www/logs/jenkins_logs"
LOGS_BASE_URL = "http://pnexus.sytes.net:8082/jenkins_logs"
if (env.GERRIT_PIPELINE == 'nightly') {
  TIMEOUT_HOURS = 6
  REGISTRY_PORT = "5002"
}

// pipeline flow variables
// base url for all jobs
logs_url = ""
// jobs definitions from config
streams = [:]
jobs = [:]
// set of jobs code for both above
jobs_code = [:]
// set of result of each job 
job_results = [:]

rnd = new Random()

// gerrit utils
gerrit = null

timestamps {
  timeout(time: TIMEOUT_HOURS, unit: 'HOURS') {
    node("${SLAVE}") {
      if (!env.GERRIT_CHANGE_ID && env.GERRIT_PIPELINE != 'nightly') {
        println("Manual run is forbidden")
        return
      }
      cleanWs(disableDeferredWipeout: true, notFailBuild: true, deleteDirs: true)
      clone_self()
      gerrit = load("${WORKSPACE}/tf-jenkins/pipelines/utils/gerrit.groovy")
      // has_gate_approvals needs cloned repo for tools
      println("Verified value to report on success: ${gerrit.VERIFIED_SUCCESS_VALUES[env.GERRIT_PIPELINE]}")
      if (env.GERRIT_PIPELINE == 'gate' && !gerrit.has_gate_approvals()) {
        println("There is no gate approvals.. skip gate")
        return
      }
      pre_build_done = false
      try {
        time_start = (new Date()).getTime()
        stage('Pre-build') {
          terminate_previous_jobs()
          evaluate_env()
          println("Streams from  config: ${streams}")
          println("Jobs from config: ${jobs}")
          archiveArtifacts(artifacts: 'global.env')
          println "Logs URL: ${logs_url}"
          gerrit.gerrit_build_started()
          currentBuild.description = "<a href='${logs_url}'>${logs_url}</a>"
          pre_build_done = true
        }

        jobs.keySet().each { name ->
          job_results[name] = [:]
          jobs_code[name] = {
            stage(name) {
              try {
                def result = wait_for_dependencies(name)
                def force_run = jobs[name].get('force-run', false)
                if (result || force_run) {
                  // TODO: add optional timeout from config - timeout(time: 60, unit: 'MINUTES')
                  run_job(name)
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
      } finally {
        println "Logs URL: ${logs_url}"
        println "Destroy VMs"
        try {
          run_job('cleanup-pipeline-workers')
        } catch(err){
        }

        // add gerrit voting +2 +1 / -1 -2
        verified = gerrit.gerrit_vote(pre_build_done, (new Date()).getTime() - time_start)
        // TODO: think how to move it into config
        if (verified > 0 && env.GERRIT_PIPELINE == 'nightly') {
          // publish stable
          // TODO: pass STABLE via env file - pass addit
          stage('publish-latest-stable') {
            run_job('publish')
            // TODO: parameters: [booleanParam(name: 'STABLE', value: true)]
          }
        }

        save_pipeline_output_to_logs()
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
    userRemoteConfigs: [[url: 'https://github.com/progmaticlab/tf-jenkins.git']],
    extensions: [
      [$class: 'CleanBeforeCheckout'],
      [$class: 'CloneOption', depth: 1],
      [$class: 'RelativeTargetDirectory', relativeTargetDir: 'tf-jenkins']
    ]
  ])
}

def evaluate_env() {
  try {
    sh """#!/bin/bash -e
      echo "export PIPELINE_BUILD_TAG=${BUILD_TAG}" > global.env
      echo "export SLAVE=${SLAVE}" >> global.env
    """

    // evaluate logs params
    if (env.GERRIT_CHANGE_ID) {
      contrail_container_tag = GERRIT_CHANGE_NUMBER + '-' + GERRIT_PATCHSET_NUMBER
      hash = env.GERRIT_CHANGE_NUMBER.reverse().take(2).reverse()
      logs_path = "${LOGS_BASE_PATH}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/${env.GERRIT_PIPELINE}_${BUILD_NUMBER}"
      logs_url = "${LOGS_BASE_URL}/gerrit/${hash}/${env.GERRIT_CHANGE_NUMBER}/${env.GERRIT_PATCHSET_NUMBER}/${env.GERRIT_PIPELINE}_${BUILD_NUMBER}"
    } else if (env.GERRIT_PIPELINE == 'nightly') {
      contrail_container_tag = 'nightly'
      logs_path = "${LOGS_BASE_PATH}/nightly/pipeline_${BUILD_NUMBER}"
      logs_url = "${LOGS_BASE_URL}/nightly/pipeline_${BUILD_NUMBER}"
    } else {
      contrail_container_tag = 'dev'
      logs_path = "${LOGS_BASE_PATH}/manual/pipeline_${BUILD_NUMBER}"
      logs_url = "${LOGS_BASE_URL}/manual/pipeline_${BUILD_NUMBER}"
    }
    sh """#!/bin/bash -e
      echo "export LOGS_HOST=${LOGS_HOST}" >> global.env
      echo "export LOGS_PATH=${logs_path}" >> global.env
      echo "export LOGS_URL=${logs_url}" >> global.env
    """
    // store default registry params. jobs can redefine them if needed in own config (VARS).
    sh """#!/bin/bash -e
      echo "export REGISTRY_IP=${REGISTRY_IP}" >> global.env
      echo "export REGISTRY_PORT=${REGISTRY_PORT}" >> global.env
      echo "export CONTAINER_REGISTRY=${REGISTRY_IP}:${REGISTRY_PORT}" >> global.env
      echo "export CONTRAIL_CONTAINER_TAG=${contrail_container_tag}" >> global.env
    """

    // store gerrit input if present. evaluate jobs
    println("Pipeline to run: ${env.GERRIT_PIPELINE}")
    project_name = env.GERRIT_PROJECT
    if (env.GERRIT_CHANGE_ID) {
      url = gerrit.resolve_gerrit_url()
      sh """#!/bin/bash -e
        echo "export GERRIT_URL=${url}" >> global.env
        echo "export GERRIT_CHANGE_ID=${env.GERRIT_CHANGE_ID}" >> global.env
        echo "export GERRIT_BRANCH=${env.GERRIT_BRANCH}" >> global.env
      """
    } else if (env.GERRIT_PIPELINE == 'nightly') {
      project_name = "tungstenfabric"
    }
    (streams, jobs) = get_jobs(project_name, env.GERRIT_PIPELINE)
  } catch (err) {
    msg = err.getMessage()
    if (err != null) {
      println("ERROR: Failed set environment ${msg}")
    }
    throw(err)
  }
}

def get_jobs(project_name, gerrit_pipeline) {
  // read main file
  def data = readYaml(file: "${WORKSPACE}/tf-jenkins/config/projects.yaml")
  // read includes
  def include_data = []
  for (item in data) {
    if (item.containsKey('include')) {
      for (file in item['include']) {
        include_data += readYaml(file: "${WORKSPACE}/tf-jenkins/config/${file}")
      }
    }
  }
  data += include_data

  // get templates
  def templates = [:]
  for (item in data) {
    if (item.containsKey('template')) {
      template = item['template']
      templates[template.name] = template
    }
  }
  // resolve parent templates
  while (true) {
    parents_found = false
    parents_resolved = false
    for (item in templates) {
      if (!item.value.containsKey('parents'))
        continue
      parents_found = true
      new_parents = []
      for (parent in item.value['parents']) {
        if (templates[parent].containsKey('parents')) {
          new_parents += parent
          continue
        }
        parents_resolved = true
        item.value['jobs'] += templates[parent]['jobs']
      }
      if (new_parents.size() > 0)
        item.value['parents'] = new_parents
      else
        item.value.remove('parents')
    }
    if (!parents_found)
      break
    if (!parents_resolved)
      throw new Exception("ERROR: Unresolvable template structure: " + templates)
  }

  // find project and pipeline inside it
  project = null
  for (item in data) {
    if (!item.containsKey('project') || item.get('project').name != project_name)
      continue
    project = item.get('project')
    break
  }
  // fill jobs from project and templates
  streams = [:]
  jobs = [:]  
  if (!project) {
    println("INFO: project ${project_name} is not defined in config")
    return [streams, jobs]
  }
  if (!project.containsKey(gerrit_pipeline)) {
    print("WARNING: project ${project_name} doesn't define pipeline ${gerrit_pipeline}")
    return [streams, jobs]
  }
  if (project[gerrit_pipeline].containsKey('templates')) {
    for (template_name in project[gerrit_pipeline].templates) {
      if (!templates.containsKey(template_name))
        throw new Exception("ERROR: template ${template_name} is absent in configuration")
      template = templates[template_name]
      update_list(streams, template.get('streams', []))
      update_list(jobs, template.get('jobs', []))
    }
  }
  // merge info from templates with project's jobs
  update_list(streams, project[gerrit_pipeline].get('streams', []))
  update_list(jobs, project[gerrit_pipeline].get('jobs', []))

  // do some checks
  // check if all deps point to real jobs
  for (item in jobs) {
    deps = item.value.get('depends-on')
    if (deps == null || deps.size() == 0)
      continue
    for (dep_name in deps) {
      if (!jobs.containsKey(dep_name))
        throw new Exception("Item ${item.key} has unknown dependency ${dep_name}")
    }
  }

  return [streams, jobs]
}

def update_list(items, new_items) {
  for (item in new_items) {
    if (item.getClass() != java.util.LinkedHashMap$Entry) {
      throw new Exception("Invalid item in config - '${item}'. It must be an entry of HashMap")
    }
    if (!items.containsKey(item.key))
      items[item.key] = item.value
    else
      items[item.key] += item.value
  }
}

def wait_for_dependencies(name) {
  def deps = jobs[name].get('depends-on')
  if (deps == null || deps.size() == 0)
    return true
  println("JOB ${name}: waiting for dependecies")
  def result = true
  // wait for all jobs even if some of them failed
  for (def dep_name in deps) {
    println("JOB ${name}: wait for dependecy ${dep_name}")
    if (!job_results.containsKey(dep_name) || !job_results[dep_name].containsKey('result')) {
      waitUntil {
        // TODO: try to use sync objects
        println("Job ${name} is still waiting for ${dep_name}")
        sleep(15)
        return job_results.containsKey(dep_name) && job_results[dep_name].containsKey('result')
      }
    }
    println("JOB ${name}: wait finished for dependency ${dep_name} with result ${job_results.get(dep_name)}")
    if (job_results[dep_name]['result'] != 'SUCCESS') {
      println("ERROR: Job ${name} - dependent job failed: ${dep_name} = ${job_results[dep_name]}")
      result = false
    }
  }
  println("JOB ${name}: wait finished with result: ${result}")
  return result
}

def job_params_to_file(name, env_file) {
  if (!jobs.containsKey(name) || !jobs[name].containsKey('vars'))
    return

  def job_name = jobs[name].get('job-name', name)
  def env_text = ""
  for (def jvar in jobs[name]['vars']) {
    env_text += "export ${jvar.key}='${jvar.value}'\n"
  }
  writeFile(file: env_file, text: env_text)
  archiveArtifacts(artifacts: env_file)
}

@NonCPS
def collect_dependent_env_files(name, deps_env_file) {
  if (!jobs.containsKey(name) || !jobs[name].containsKey('depends-on'))
    return
  def deps = jobs[name].get('depends-on')
  if (deps == null || deps.size() == 0)
    return
  println("JOB ${name}: deps: ${deps}")
  def content = ''
  for (def dep_name in deps) {
    def job_name = jobs[dep_name].get('job-name', dep_name)
    def job_rnd = job_results[dep_name]['job-rnd']
    dir("${WORKSPACE}") {
      findFiles(glob: "${job_name}-${job_rnd}/*.env").each { filew ->
        content += readFile(filew.getPath())
      }
    }
  }
  def lines = content.split('\n').findAll { it.size() > 0 }
  if (lines.size() == 0)
    return
  content = lines.join('\n') + '\n'
  println("JOB ${name}: deps_env_file: ${deps_env_file}")
  writeFile(file: deps_env_file, text: content)
  archiveArtifacts(artifacts: deps_env_file)
}

def run_job(name) {
  println("JOB ${name}: entering run_job")
  // final cleanup job is not in config
  def job_name = jobs.containsKey(name) ? jobs[name].get('job-name', name) : name
  def stream = jobs.containsKey(name) ? jobs[name].get('stream', name) : name
  def job_number = null
  def job_rnd = "${rnd.nextInt(99999)}"
  def vars_env_file = "vars.${job_name}.${job_rnd}.env"
  def deps_env_file = "deps.${job_name}.${job_rnd}.env"
  def run_err = null
  try {
    job_results[name]['job-rnd'] = job_rnd
    job_params_to_file(name, vars_env_file)
    collect_dependent_env_files(name, deps_env_file)
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
      def cause_msg = err.getCauses()[0].getShortDescription()
      def build_num_matcher = cause_msg =~ /#\d+/
      if (build_num_matcher.find()) {
        job_number = ((build_num_matcher[0] =~ /\d+/)[0]).toInteger()
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

def terminate_previous_jobs() {
  if (!env.GERRIT_CHANGE_ID)
    return

  def runningBuilds = Jenkins.getInstanceOrNull().getView('All').getBuilds().findAll() { it.getResult().equals(null) }
  for (rb in runningBuilds) {
    def action = rb.allActions.find {it in hudson.model.ParametersAction}
    if (!action)
      continue
    gerrit_change_number = action.getParameter("GERRIT_CHANGE_NUMBER")
    if (!gerrit_change_number) {
      continue
    }
    change_num = gerrit_change_number.value.toInteger()
    patchset_num = action.getParameter("GERRIT_PATCHSET_NUMBER").value.toInteger()
    if (GERRIT_CHANGE_NUMBER.toInteger() == change_num && GERRIT_PATCHSET_NUMBER.toInteger() > patchset_num) {
      rb.doStop()
      println "Build $rb has been aborted when a new patchset is created"
    }
  }
}

def save_pipeline_output_to_logs() {
  println("BUILD_URL = ${BUILD_URL}consoleText")
  withCredentials(
    bindings: [
      sshUserPrivateKey(credentialsId: 'logs_host', keyFileVariable: 'LOGS_HOST_SSH_KEY', usernameVariable: 'LOGS_HOST_USERNAME')]) {
    sh """#!/bin/bash -e
      set -x
      curl ${BUILD_URL}consoleText > pipelinelog.txt 
      ssh -i ${LOGS_HOST_SSH_KEY} -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${LOGS_HOST_USERNAME}@${LOGS_HOST} "mkdir -p ${logs_path}"
      rsync -a -e "ssh -i ${LOGS_HOST_SSH_KEY} -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" pipelinelog.txt ${LOGS_HOST_USERNAME}@${LOGS_HOST}:${logs_path} 
    """
  }
  archiveArtifacts artifacts: "pipelinelog.txt"
  echo "Output logs saved at ${logs_url}/pipelinelog.txt"
}
