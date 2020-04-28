import groovy.json.JsonSlurper
import groovy.json.JsonOutput

// TODO Fill up list of projects that can't be run in concurrent mode
SERIAL_PROJECTS = ['Juniper/contrail-kolla-ansible']

// Function find base build fits to be the base build
// get its base builds list if any, and then iterate over the list
// check if items of the list is still working or SUCCESS or FAILURE.
// If next build is fit to be a base build, the function add its id to BASE_BUILDS_LIST
// return false if base build not found or build_id if foundпше
// save BASE_BUILD_ID_LIST sting including base builds chain like "23,22,20"
def save_base_builds() {
  def builds_map = _prepare_builds_map()

  def base_build_no = false
  builds_map.any { build_id, build_map ->
    if (!build_id || !_is_branch_fit(build_id))
      continue
    // Skip current or started later builds
    if (build_id.toInteger() >= BUILD_ID.toInteger()) {
      return false
    }
    if (build_map['status'] != 'null') {
      // build has been finished
      if (check_build_is_not_failed(build_id)) { // We not need base build!
        return true
      } // else just skip the build
    } else { // build is running
      // Wait for build chain will be prepared
      def base_chain = _wait_for_chain_calculated(build_id)
      if (base_chain == "-1") { // build fails before can calculate BASE_BUILD_ID_LIST
        return false
      }
      if (base_chain) { // base_chain is not empty string
        if (_check_base_chain_is_not_failed(base_chain) == false) { // Some of base builds fails
          return false
        }
        base_chain = "${build_id}," + base_chain
      } else { // base_chain is empty, add the only this build to chain
        base_chain = build_id.toString()
      }
      // We found base build! Save base_chain in global.vars
      base_build_no = build_id
      sh """#!/bin/bash -e
        echo "export BASE_BUILD_ID_LIST=${base_chain}" >> global.env
      """
      return true
    }
  }

  if (base_build_no) {
    // Add base patchset info to the build
    save_pachset_info(base_build_no)
  } else {
    // If a base build not found save BASE_BUILD_ID_LIST anyway, because it needs
    // to detect if process of the base build search is finished
    sh """#!/bin/bash -e
      echo "export BASE_BUILD_ID_LIST=" >> global.env
    """
  }

  archiveArtifacts(artifacts: 'global.env')

  return base_build_no
}

// Function find build with build_id and gets it's global env.
// Read global.env and wait until variable BASE_BUILD_ID_LIST will be added there
// or if build failed.
// return value of BASE_BUILD_ID_LIST if it has been found
// or -1 if build fails
def _wait_for_chain_calculated(build_id) {
  def base_id_list = "-1"
  waitUntil {
    def build = _get_build_by_id(build_id)
    base_id_list = _find_base_list(build)
    if (build.getResult() != null && base_id_list == "-1") {
      // build finishes but no base_id_list was found
      return true
    }
    return base_id_list != '-1'
  }

  return base_id_list
}

// Function get global.env artifact and find there BASE_BUILD_ID_LIST
// Return value of BASE_BUILD_ID_LIST of has been found
// Otherwise retirn "-1"
def _find_base_list(build) {
  def base_id_list = "-1"
  def artifactManager = build.getArtifactManager()
  if (!artifactManager.root().isDirectory())
    return base_id_list

  def fileList = artifactManager.root().list()
  fileList.any {
    def file = it
    if (!file.toString().contains('global.env'))
      continue

    // extract global.env artifact for each build if exists
    def fileText = it.open().getText()
    fileText.split("\n").each {
      def line = it
      // Check if BASE_BUILD_ID_LIST exists in global.env file
      if (line.contains('BASE_BUILD_ID_LIST')) {
        def bil = line.split('=')
        if (bil.size() == 2) {
          base_id_list = bil[1].trim()
        } else { // looks like BASE_BUILD_ID_LIST= empty string
          base_id_list = ""
        }
        return true
      }
    }
  }
  return base_id_list
}

def get_build_result_by_id(build_id) {
  def build = _get_build_by_id(build_no)
  return build ? build.getResult().toString() : null
}

// find and return build of gate pipeline using build_id
// otherwise return null
def _get_build_by_id(build_no) {
  if (!build_no.isInteger())
    return null
  def gate_pipeline = jenkins.model.Jenkins.instance.getItem(env.JOB_NAME)
  def builds = gate_pipeline.getBuilds()

  for (def i=0; i<builds.size(); i++) {
    if (builds[i].getId().toInteger() == build_no.toInteger()) {
      return builds[i]
    }
  }
  return null
}

// Function parse base chain and check if all builds is not failed
// if function meet successfully finished build in the chain, this
// build and all its base builds remove from the chain (chain shortened)
// Return true if NOT meet failure build and chain
// and false if meet some failures
def _check_base_chain_is_not_failed(base_chain) {
  if (base_chain == "")
    return true
  def is_not_failed = true
  def arr_chain = base_chain.split(",")
  arr_chain.any { build_id ->
    if (get_build_result_by_id(build_id) == null) // is not finished yes - skip the build
      return false
    if (check_build_is_not_failed(build_id)) {
      return false
    } else {
      is_not_failed = false
      return true
    }
  }

  return is_not_failed
}

// Function return ordered map with builds with data needed for find
// and process base build
def _prepare_builds_map() {
  def gate_pipeline = jenkins.model.Jenkins.instance.getItem(env.JOB_NAME)
  def builds_map = [:]

  gate_pipeline.builds.each {
    def build = it
    def build_id = build.getId()
    def build_status = build.getResult().toString()
    def build_env = build.getEnvironment()

    builds_map[build_id] = ['status' : build_status ,
                            'branch' : build_env['GERRIT_BRANCH'],
                            'project' : build_env['GERRIT_PROJECT']]
  }

  return builds_map
}

// function return true if project can be run concurrently -
// it has contrail releases/branches structure
// otherwise it returns false
def is_concurrent_project() {
  return !SERIAL_PROJECTS.contains(GERRIT_PROJECT)
}

// Function check if build's branch fit to current project branch
// Return true if we can use this build as a base build for current running pipeline
// Otherwise return false
def _is_branch_fit(build_id) {
  def build = _get_build_by_id(build_id)
  if (is_concurrent_project()) {
    // Project has contrail releases structure
    // Branch of the base build must be the same
    if (GERRIT_BRANCH != build.getEnvironment()['GERRIT_BRANCH'])
      return false
  } else {
    // Project has its own releases structure
    // Branch of the base build must be master
    if (build.getEnvironment()['GERRIT_BRANCH'] != 'master')
      return false
  }

  return true
}

// Function check build using build_no is failed
def check_build_is_not_failed(build_no) {
  // Get the build
  def gate_pipeline = jenkins.model.Jenkins.instance.getItem(env.JOB_NAME)
  def build = null

  gate_pipeline.getBuilds().any {
    if (it.getEnvVars().BUILD_ID.toInteger() == build_no.toInteger()) {
      build = it
      return true
    }
  }
  if (build.getResult() != null && _gate_get_build_state(build) == 'FAILURE') {
    return false
  }
  return true
}

// The function get build's artifacts, find there VERIFIED,
// and check if it is integer and more than 0 return SUCCESS
// and return FAILRUE in another case
// !!! Works only if build has been finished! Check getResult() before call this function
def _gate_get_build_state(build) {
  def result = "FAILURE"
  def artifactManager =  build.getArtifactManager()
  if (!artifactManager.root().isDirectory())
    return result

  def fileList = artifactManager.root().list()
  fileList.each {
    def file = it
    if (!file.toString().contains('global.env'))
      continue
    // extract global.env artifact for each build if exists
    def fileText = it.open().getText()
    fileText.split("\n").each {
      def line = it
      if (line.contains('VERIFIED')) {
        def verified = line.split('=')[1].trim()
        if (verified.isInteger() && verified.toInteger() > 0)
          result = "SUCCESS"
      }
    }
  }

  return result
}

// Function find the build with build_no and wait it finishes with any result
def wait_pipeline_finished(build_no) {
  waitUntil {
    def res = _get_pipeline_result(build_no)
    return ! res
  }
}

// Put all this staff in separate function due to Serialisation under waitUntil
def _get_pipeline_result(build_no) {
  def job = jenkins.model.Jenkins.instance.getItem(env.JOB_NAME)
  // Get DEVENV_TAG for build_no pipeline
  def build = null
  job.builds.any {
    if (build_no.toInteger() == it.getEnvVars().BUILD_ID.toInteger()) {
      build = it
    }
  }
  return build.getResult() == null
}

// Check if pipeline with the same GERRIT_PROJECT is running
// and if it is then wait until finishes
def wait_until_project_pipeline() {
  def builds_map = _prepare_builds_map()
  def same_project_build = false
  builds_map.any { build_id, build_map ->
    if (build_map['project'] == GERRIT_PROJECT && build_map['status'] == 'null' &&
       build_id.toInteger() < BUILD_ID.toInteger()) {
      same_project_build = build_id
      return true
    }
  }

  if (same_project_build) {
    waitUntil {
      return get_build_result_by_id(same_project_build) != null
    }
  }
}

// function read patchset_info artiface from base build if exists
// read pachset_info of current build
// union all patchset_info in one array
// and write all info to patchset_info artifact of corrent build
def save_pachset_info(base_build_no) {
  if (!(base_build_no && base_build_no.isInteger()))
    return
  def res_json = get_result_patchset(base_build_no)
  if (!res_json)
    return false
  writeFile(file: 'patchsets-info.json', text: res_json)
  archiveArtifacts(artifacts: "patchsets-info.json")
}

// all JSON calsulate to separate function
def get_result_patchset(base_build_no) {
  def new_patchset_info_text = readFile("patchsets-info.json")
  def sl = new JsonSlurper()
  def new_patchset_info = sl.parseText(new_patchset_info_text)
  def base_patchset_info = ""
  // Read patchsets-info from base build
  def base_build = _get_build_by_id(base_build_no)
  def artifactManager =  base_build.getArtifactManager()
  if (artifactManager.root().isDirectory()) {
    def fileList = artifactManager.root().list()
    fileList.any {
      def file = it
      if (file.toString().contains('patchsets-info.json')) {
        // extract global.env artifact for each build if exists
        base_patchset_info = it.open().getText()
        return true
      }
    }
  }
  def sl2 = new JsonSlurper()
  def old_patchset_info = sl2.parseText(base_patchset_info)
  if (old_patchset_info instanceof java.util.ArrayList ) {
    def result_patchset_info = old_patchset_info + new_patchset_info
    def json_result_patchset_info = JsonOutput.toJson(result_patchset_info)
    return json_result_patchset_info
  }
  return false
}

// Function read global.env line by len and if met the line
// with BASE_BUILD_ID_LIST remove it from file
def cleanup_globalenv_vars() {
  def new_patchset_info_text = readFile("global.env")
  new_patchset_info_text.eachLine{ line ->
    if (! line.contains('BASE_BUILD_ID_LIST')) {
      sh """#!/bin/bash -e
          echo "${line}" >> global.env
        """
    }
  }

  archiveArtifacts(artifacts: 'global.env')
}

return this