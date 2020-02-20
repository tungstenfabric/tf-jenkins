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
// list of pure info about jobs from config with additional parameters
jobs_from_config = [:]
// list of top jobs from config: fetch, build, unit, lint
top_jobs_to_run = []
// list of test configurations in format ${deployer}_${orchestrator}
test_configuration_names = []
// set of jobs code for both above
top_jobs_code = [:]
inner_jobs_code = [:]
// set of result of each job 
job_results = [:]

rnd = new Random()

// Please note: two similar jobs with similar parameters can be run as one job with two parents.
//              right now there in no such cases but please be careful with addition new jobs

timestamps {
  timeout(time: TIMEOUT_HOURS, unit: 'HOURS') {
    node("${SLAVE}") {
      if (!env.GERRIT_CHANGE_ID && env.GERRIT_PIPELINE != 'nightly') {
        println("Manual run is forbidden")
        return
      }
      if (env.GERRIT_PIPELINE == 'gate' && ! has_gate_approvals()) {
        println("There os no gate approvals.. skip gate")
        return
      }
      pre_build_done = false
      try {
        time_start = (new Date()).getTime()
        stage('Pre-build') {
          terminate_previous_jobs()
          clone_self()
          evaluate_env()
          archiveArtifacts artifacts: 'global.env'
          println "Logs URL: ${logs_url}"
          println 'Top jobs to run: ' + top_jobs_to_run
          println 'Test configurations: ' + test_configuration_names
          gerrit_build_started()
          currentBuild.description = "<a href='${logs_url}'>${logs_url}</a>"
          pre_build_done = true
        }

        if ('fetch-sources' in top_jobs_to_run) {
          stage('Fetch') {
            run_job('fetch-sources', [job: 'fetch-sources'])
          }
        }

        // build independent jobs
        ['test-unit', 'test-lint'].each { name ->
          if (name in top_jobs_to_run) {
            top_jobs_code[name] = {
              stage(name) {
                run_job(name, [job: name])
              }
            }
          }
        }

        // declaration of deploy platform parts
        test_configuration_names.each { name ->
          top_jobs_code["Deploy platform for ${name}"] = {
            stage("Deploy platform for ${name}") {
              println "Started deploy platform for ${name}"
              timeout(time: 60, unit: 'MINUTES') {
                run_job("deploy-platform-${name}", [job: "deploy-platform-${name}"])
              }
            }
          }
        }

        // declaration of deploy TF parts and functional tests run after
        test_configuration_names.each { name ->
          inner_jobs_code["Deploy TF for ${name}"] = {
            stage("Deploy TF for ${name}") {
              println "Started deploy TF and test for ${name}"
              // just wait for deploy-platform job - build job just is a previous step
              waitUntil {
                sleep(15)
                return job_results["deploy-platform-${name}"].containsKey('result')
              }
              if (job_results["deploy-platform-${name}"]['result'] != 'SUCCESS') {
                unstable("Deploy platform failed - skip deploy TF and tests for ${name}")
                return
              }

              try {
                top_job_number = job_results["deploy-platform-${name}"]['number']
                run_job(
                  "deploy-tf-${name}",
                  [job: "deploy-tf-${name}",
                   parameters: [
                    string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                  ]])
                def test_jobs = [:]
                get_test_job_names(name).each { test_name ->
                  test_jobs["${test_name} for deploy-tf-${name}"] = {
                    stage("${test_name}-${name}") {
                      // next variable must be taken again due to closure limitations for free variables
                      top_job_number = job_results["deploy-platform-${name}"]['number']
                      run_job(
                        "${test_name}-${name}",
                        [job: test_name,
                         parameters: [
                          string(name: 'DEPLOY_PLATFORM_JOB_NAME', value: "deploy-platform-${name}"),
                          string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                        ]])
                    }
                  }
                }
                parallel test_jobs
              } finally {
                stage('Collect logs and cleanup') {
                  top_job_number = job_results["deploy-platform-${name}"]['number']
                  println "Trying to collect logs and cleanup workers for ${name} job ${top_job_number}"
                  run_job(
                    "collect-logs-and-cleanup",
                    [job: "collect-logs-and-cleanup",
                     parameters: [
                      string(name: 'DEPLOY_PLATFORM_JOB_NAME', value: "deploy-platform-${name}"),
                      string(name: 'DEPLOY_PLATFORM_JOB_NUMBER', value: "${top_job_number}"),
                      booleanParam(name: 'COLLECT_SANITY_LOGS', value: job_results["deploy-tf-${name}"]['result'] == 'SUCCESS'),
                    ]])
                }
              }
            }
          }
        }

        // check if build is enabled
        if ('build' in top_jobs_to_run) {
          // add publish job into inner_jobs_code to be run in parallel with deploy but after build
          if (env.GERRIT_PIPELINE == 'nightly') {
            inner_jobs_code["Publish TF containers to docker hub"] = {
              stage('publish-latest') {
                run_job(
                  'publish',
                  [job: 'publish',
                   parameters: [booleanParam(name: 'STABLE', value: false)]])
              }
            }
          }
          top_jobs_code['Build images for testing'] = {
            stage('build') {
              run_job('build', [job: 'build'])
            }
            parallel inner_jobs_code
          }
        } else {
          top_jobs_code['Test with nightly images'] = {
            parallel inner_jobs_code
          }
        }

        // run jobs in parallel
        parallel top_jobs_code
      } finally {
        println "Logs URL: ${logs_url}"
        println "Destroy VMs"
        try {
          run_job('cleanup-pipeline-workers', [job: 'cleanup-pipeline-workers'])
        } catch(err){
        }

        // add gerrit voting +1/-1
        verified = gerrit_vote(pre_build_done, (new Date()).getTime() - time_start)

        if (verified == 1 && env.GERRIT_PIPELINE == 'nightly' && 'build' in top_jobs_to_run) {
          // publish stable
          stage('publish-latest-stable') {
            run_job(
              'publish',
              [job: 'publish', 
               parameters: [booleanParam(name: 'STABLE', value: true)]])
          }
        }

        save_output_to_nexus()
      }
    }
  }
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

    // store gerrit input if present. evaluate jobs
    println "Pipeline to run: ${env.GERRIT_PIPELINE}"
    if (env.GERRIT_CHANGE_ID) {
      url = resolve_gerrit_url()
      sh """#!/bin/bash -e
        echo "export GERRIT_URL=${url}" >> global.env
        echo "export GERRIT_CHANGE_ID=${env.GERRIT_CHANGE_ID}" >> global.env
        echo "export GERRIT_BRANCH=${env.GERRIT_BRANCH}" >> global.env
      """
      get_jobs(env.GERRIT_PROJECT, env.GERRIT_PIPELINE)
    } else if (env.GERRIT_PIPELINE == 'nightly') {
      get_jobs("tungstenfabric", env.GERRIT_PIPELINE)
    }
    println "Evaluated jobs to run: ${jobs_from_config}"
    def possible_top_jobs = ['test-lint', 'test-unit', 'build', 'fetch-sources']
    for (item in jobs_from_config) {
      if (item.getKey() in possible_top_jobs) {
        top_jobs_to_run += item.getKey()
      } else {
        test_configuration_names += item.getKey()
      }
    }

    // evaluate registry params
    // if we have fetch-sources then it means that we have build stage thus we have to use own registry for deploy
    if ('fetch-sources' in top_jobs_to_run) {
      sh """#!/bin/bash -e
        echo "export REGISTRY_IP=${REGISTRY_IP}" >> global.env
        echo "export REGISTRY_PORT=${REGISTRY_PORT}" >> global.env
        echo "export CONTAINER_REGISTRY=${REGISTRY_IP}:${REGISTRY_PORT}" >> global.env
        echo "export CONTRAIL_CONTAINER_TAG=${contrail_container_tag}" >> global.env
      """
    }
  } catch (err) {
    msg = err.getMessage()
    if (err != null) {
      println "Failed set environment ${msg}"
    }
    throw(err)
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

def get_jobs(project, gerrit_pipeline) {
  def data = readYaml file: "${WORKSPACE}/tf-jenkins/config/projects.yaml"
  def templates = [:]
  for (item in data) {
    if (item.containsKey('project-template')) {
      template = item.get('project-template')
      templates[template.name] = template
    }
  }
  for (item in data) {
    if (!item.containsKey('project') || item.get('project').name != project)
      continue
    project = item.get('project')
    if (project.containsKey('templates')) {
      for (template in project.templates) {
        if (templates[template].get(gerrit_pipeline) && templates[template].get(gerrit_pipeline).get('jobs')) {
          for (job_item in templates[template].get(gerrit_pipeline).jobs) {
            add_job(job_item)
          }
        }
      }
    }
    if (project.get(gerrit_pipeline) && project.get(gerrit_pipeline).get('jobs')) {
      for (job_item in project.get(gerrit_pipeline).jobs) {
        add_job(job_item)
      }
    }
  }
}

def add_job(job_item) {
  if (job_item instanceof String) {
    jobs_from_config[job_item] = [:]
  } else {
    job = job_item.entrySet().iterator().next()
    jobs_from_config[job.getKey()] = job.getValue()
  }
}

def notify_gerrit(msg, verified=0, submit=false) {
  if (!env.GERRIT_HOST) {
    // looks like it's a nightly pipeline
    return
  }
  println "Notify gerrit verified=${verified}, submit=${submit}, msg=\n${msg}"
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

def has_gate_approvals() {
  if (!env.GERRIT_HOST) {
    // looks like it's a nightly pipeline
    return
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
    try {
      sh """
        ${WORKSPACE}/tf-jenkins/infra/gerrit/check_approvals.py \
          --gerrit ${url} \
          --user ${GERRIT_API_USER} \
          --password ${GERRIT_API_PASSWORD} \
          --review ${GERRIT_CHANGE_ID} \
          --branch ${GERRIT_BRANCH}
      """
    } catch (err) {
      print "Exeption in check_approvals.py"
      def msg = err.getMessage()
      if (msg != null) {
        print msg
      }
    }
  }
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
    notify_gerrit(msg)
  } catch (err) {
    print "Failed to provide comment to gerrit "
    def msg = err.getMessage()
    if (msg != null) {
      print msg
    }
  }
}

def gerrit_vote(pre_build_done, full_duration) {
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
        msg += "\n- " + get_gerrit_msg_for_job(name, status, job_result.get('duration'))
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
        msg += "\n- " + get_gerrit_msg_for_job(name, status, duration)
      }
      def voting = jobs_from_config[name].get('voting', true)
      if (!voting) {
        msg += ' (non-voting)'
      }
      if (voting && status != 'SUCCESS') {
        passed = false
      }
    }

    def duration_string = get_duration_string(full_duration)
    def verified = 1
    if (passed) {
      msg = "Jenkins Build Succeeded (${env.GERRIT_PIPELINE}) ${duration_string}\n" + msg
    } else {
      msg = "Jenkins Build Failed (${env.GERRIT_PIPELINE}) ${duration_string}\n" + msg
      verified = -1
    }
    notify_gerrit(msg, verified)
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

def get_gerrit_msg_for_job(name, status, duration) {
  def duration_string = get_duration_string(duration)
  return "${name} ${logs_url}/${name} : ${status} ${duration_string}"
}

def get_duration_string(duration) {
  if (duration == null) {
    return ""
  }
  d = (int)(duration/1000)
  return String.format("in %dh %dm %ds", (int)(d/3600), (int)(d/60)%60, d%60)
}

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

def job_params_to_file(job_name) {
  if (!jobs_from_config.containsKey(job_name) || !jobs_from_config[job_name].containsKey('vars'))
    return

  env_file = "${job_name}.env"
  env_text = ""
  for (jvar in jobs_from_config[job_name]['vars']) {
    env_text += "export ${jvar.getKey()}='${jvar.getValue()}'\n"
  }
  writeFile(file: env_file, text: env_text)
  archiveArtifacts artifacts: "${env_file}"
}

def run_job(name, params) {
  def job_name = params['job']
  job_results[name] = [:]
  try {
    job_params_to_file(name)
    params['parameters'] = params.get('parameters', []) + [
      string(name: 'RANDOM', value: "${rnd.nextInt(99999)}"),
      string(name: 'PIPELINE_NAME', value: "${JOB_NAME}"),
      string(name: 'PIPELINE_NUMBER', value: "${BUILD_NUMBER}"),
      [$class: 'LabelParameterValue', name: 'NODE_NAME', label: "${NODE_NAME}"]]
    def job = build(params)
    job_results[name]['result'] = job.getResult()
    job_results[name]['number'] = job.getNumber()
    job_results[name]['duration'] = job.getDuration()
    println "Finished ${name} with SUCCESS"
  } catch (err) {
    println "Failed ${name}"
    job_results[name]['result'] = 'FAILURE'
    msg = err.getMessage()
    if (msg != null) {
      println msg
    }
    // get build num from exception and find job to get duration and result
    try {
      def cause_msg = err.getCauses()[0].getShortDescription()
      def build_num_matcher = cause_msg =~ /#\d+/
      if (build_num_matcher.find()) {
        def build_num = ((build_num_matcher[0] =~ /\d+/)[0]).toInteger()
        def job = Jenkins.getInstanceOrNull().getItemByFullName(job_name).getBuildByNumber(build_num)
        job_results[name]['result'] = job.getResult()
        job_results[name]['number'] = job.getNumber()
        job_results[name]['duration'] = job.getDuration()
      }
    } catch(e) {
      println("Error in obtaining failed job result ${err.getMessage()}")
    }
    // re-throw error
    throw(err)
  }
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
  println "BUILD_URL = ${BUILD_URL}consoleText"
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