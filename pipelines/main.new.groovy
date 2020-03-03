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
          archiveArtifacts(artifacts: 'global.env')
          println "Logs URL: ${logs_url}"
          gerrit.gerrit_build_started()
          currentBuild.description = "<a href='${logs_url}'>${logs_url}</a>"
          pre_build_done = true
        }

        jobs.each { item ->
          jobs_code[job.key] = {
            stage(item.key) {
              result = wait_for_dependencies(item.key)
              force_run = item.value.get('force-run', false)
              if (result || force_run) {
                // TODO: add optional timeout from config - timeout(time: 60, unit: 'MINUTES')
                run_job(item.key)
              } else {
                job_results[name]['number'] = -1
                job_results[name]['duration'] = 0
                job_results[name]['result'] = 'NOT_RUN'
              }
            }
          }
        }

        // run jobs in parallel
        parallel jobs_code
      } finally {
        println "Logs URL: ${logs_url}"
        println "Destroy VMs"
        try {
          run_job('cleanup-pipeline-workers', [job: 'cleanup-pipeline-workers'])
        } catch(err){
        }

        // add gerrit voting +2 +1 / -1 -2
        verified = gerrit.gerrit_vote(pre_build_done, (new Date()).getTime() - time_start)
        // TODO: think how to move it into config
        if (verified > 0 && env.GERRIT_PIPELINE == 'nightly') {
          // publish stable
          stage('publish-latest-stable') {
            run_job(
              'publish',
              [job: 'publish', 
               parameters: [booleanParam(name: 'STABLE', value: true)]])
          }
        }

        save_pipeline_output_to_nexus()
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
      url = resolve_gerrit_url()
      sh """#!/bin/bash -e
        echo "export GERRIT_URL=${url}" >> global.env
        echo "export GERRIT_CHANGE_ID=${env.GERRIT_CHANGE_ID}" >> global.env
        echo "export GERRIT_BRANCH=${env.GERRIT_BRANCH}" >> global.env
      """
    } else if (env.GERRIT_PIPELINE == 'nightly') {
      project_name = "tungstenfabric"
    }
    (streams, jobs) = get_jobs(project_name, env.GERRIT_PIPELINE)
    println("Streams from  config: ${streams}")
    println("Jobs from config: ${jobs}")
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
  def data = readYaml(file: "${WORKSPACE}/tf-jenkins/config/projects.new.yaml")
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
  if (!project)
    throw new Exception("ERROR: Unknown project: ${project_name}")
  if (!project.containsKey(gerrit_pipeline)) {
    print("WARNING: project ${project_name} doesn't define pipeline ${gerrit_pipeline}")
    return
  }
  // fill jobs from project and templates
  streams = [:]
  jobs = [:]  
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
  return [streams, jobs]
}

def update_list(items, new_items) {
  for (item in new_items) {
    if (!items.containsKey(item.key))
      items[item.key] = item.value
    else
      items[item.key] += item.value
  }
}

def job_params_to_file(job, job_rnd) {
  if (!jobs[job].containsKey('vars'))
    return

  def job_name = jobs[job].get('job-name', job)
  env_file = "vars.${job_name}-${job_rnd}.env"
  env_text = ""
  for (jvar in jobs[job]['vars']) {
    env_text += "export ${jvar.key}='${jvar.value}'\n"
  }
  writeFile(file: env_file, text: env_text)
  archiveArtifacts artifacts: "${env_file}"
}

def wait_for_dependencies(name) {
  deps = jobs[name].get('depends-on')
  if (!deps or deps.size())
    return true
  result = true
  // wait for all jobs even if some of them failed
  for (dep_name in deps) {
    waitUntil {
      // TODO: try to use sync objects
      sleep(15)
      return job_results[dep_name].containsKey('result')
    }
    if (job_results[dep_name]['result'] != 'SUCCESS') {
      println("ERROR: Job ${name} - dependent job failed: ${dep_name} = ${job_results[dep_name]}")
      result = false
    }
  }
  return result
}

def run_job(name) {
  def job_name = jobs[name].get('job-name', job)
  job_results[name] = [:]
  def job = null
  err = null
  try {
    def job_rnd = "${rnd.nextInt(99999)}"
    job_results[name]['job-rnd'] = job_rnd
    job_params_to_file(name, job_rnd)
    params['parameters'] = [
      string(name: 'RANDOM', value: job_rnd),
      string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
      string(name: 'PIPELINE_NUMBER', value: "${BUILD_NUMBER}"),
      [$class: 'LabelParameterValue', name: 'NODE_NAME', label: "${NODE_NAME}"]]
    job = build(params)
    println("Finished ${name} with SUCCESS")
  } catch (err) {
    println("Failed ${name} with errors")
    job_results[name]['result'] = 'FAILURE'
    msg = err.getMessage()
    if (msg != null) {
      println(msg)
    }
    // get build num from exception and find job to get duration and result
    try {
      def cause_msg = err.getCauses()[0].getShortDescription()
      def build_num_matcher = cause_msg =~ /#\d+/
      if (build_num_matcher.find()) {
        def build_num = ((build_num_matcher[0] =~ /\d+/)[0]).toInteger()
        job = Jenkins.getInstanceOrNull().getItemByFullName(job_name).getBuildByNumber(build_num)
      }
    } catch(e) {
      println("Error in obtaining failed job result ${err.getMessage()}")
    }
  }
  if (job) {
    def job_number = job.getNumber()
    job_results[name]['number'] = job_number
    job_results[name]['duration'] = job.getDuration()
    job_results[name]['result'] = job.getResult()
    copyArtifacts(filter: '*.env', fingerprintArtifacts: true, projectName: '${job_name}', selector: specific('${job_number}'))
  }
  // re-throw error
  if (err)
    throw(err)
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

def save_output_to_nexus() {
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