import groovy.json.JsonSlurper
import groovy.json.JsonOutput

// Constants
GATING_PIPELINE = 'pipeline-gate-opencontrail-c'
// TODO Fill up the normal projectls list
NORMAL_PROJECTS = ['Juniper/contrail-ansible-deployer',
                   'Juniper/contrail-container-builder']

// Function find base build fits to be the base build
// get its base builds list if any, and then iterate over the list
// check if items of the list is still working or SUCCESS or FAILURE.
// If next build is fit to be a base build, the function add its id to BASE_BUILDS_LIST
// return false if base build not found or build_id if foundпше
// save BASE_BUILD_ID_LIST sting including base builds chain like "23,22,20"
def save_base_builds(){
  def builds_map = _prepare_builds_map()

  def base_build_no = false

  println("DEBUG: Builds map prepared : ${builds_map}")
  builds_map.any { build_id, build_map ->

    println("DEBUG: Check for fit to base build no ${build_id}")
    if( build_id && _is_branch_fit(build_id) ){
      // Skip current or started later builds
      if(build_id.toInteger() >= BUILD_ID.toInteger()){
        println("DEBUG: Skip current or started later builds")
        return false
      }

      if(build_map['status'] != 'null'){
        println("DEBUG: found finished build") // build has been finished
        if(check_build_is_not_failed(build_id)){ // We not need base build!
          println("DEBUG: We not need base build!")
          return true
        } // else just skip the build
      }else{ // build is running
        println("DEBUG: Found runnig build looks like a base")
        // Wait for build chain will be prepared
        def base_chain = _wait_for_chain_calculated(build_id)
        if(base_chain == "-1"){ // build fails before can calculate BASE_BUILD_ID_LIST
          println("DEBUG: Build failed before BASE_BUILD_ID_LIST has been calculated")
          return false
        }
        if(base_chain){ // base_chain is not empty string
          base_chain = _check_base_chain_is_not_failed(base_chain)
          if(base_chain == false){ // Some of base builds fails
            println("DEBUG: Some of base build fails")
            return false
          }
          base_chain = "${build_id}," + base_chain
        }else{ // base_chain is empty, add the only this build to chain
          println("DEBUG: base_chain is empty, add the only this build to chain")
          base_chain = build_id.toString()
        }
        println("DEBUG: Base build found. Base build = ${build_id} base_chain = ${base_chain}")
        // We found base build! Save base_chain in global.vars
        base_build_no = build_id
        sh """#!/bin/bash -e
          echo "export BASE_BUILD_ID_LIST=${base_chain}" >> global.env
        """
        archiveArtifacts(artifacts: 'global.env')
        return true
      }
    }
  }

  // If a base build not found save BASE_BUILD_ID_LIST anyway, because it needs
  // to detect if process of the base build search is finished
  if(! base_build_no){
        sh """#!/bin/bash -e
        echo "export BASE_BUILD_ID_LIST=" >> global.env
        """
        archiveArtifacts(artifacts: 'global.env')
  }

  return base_build_no
}

// Function find build with build_id and gets it's global env.
// Read global.env and wait until variable BASE_BUILD_ID_LIST will be added there
// or if build failed.
// return value of BASE_BUILD_ID_LIST if it has been found
// or -1 if build fails
def _wait_for_chain_calculated(build_id){
  def base_id_list = "-1"
  println("DEBUG: Try to wait if base chain calculates for ${build_id}")
  waitUntil {
    def build = _get_build_by_id(build_id)
    base_id_list = _find_base_list(build)
    if(build.getResult() != null && base_id_list == "-1"){
      // build finishes but no base_id_list was found
      println("DEBUG: build finishes but no base_id_list was found")
      return true
    }
    return base_id_list != '-1'
  }

  println("DEBUG: We found base_id_lis = ${base_id_list}")
  return base_id_list
}

// Function get global.env artifact and find there BASE_BUILD_ID_LIST
// Return value of BASE_BUILD_ID_LIST of has been found
// Otherwise retirn "-1"
def _find_base_list(build){
  def base_id_list = "-1"
  def artifactManager =  build.getArtifactManager()
  if (artifactManager.root().isDirectory()) {
    def fileList = artifactManager.root().list()
    fileList.any {
      def file = it
      if(file.toString().contains('global.env')) {
        // extract global.env artifact for each build if exists
        def fileText = it.open().getText()
        fileText.split("\n").each {
          def line = it
          // Check if BASE_BUILD_ID_LIST exists in global.env file
          if(line.contains('BASE_BUILD_ID_LIST')) {
            def bil = line.split('=')
            if(bil.size() == 2){
              base_id_list = bil[1].trim()
            }else{ // looks like BASE_BUILD_ID_LIST= empty strinf
              base_id_list = ""
            }
            return true
          }
        }
      }
    }
  }
  println("DEBUG: Found base id list = ${base_id_list}")
  return base_id_list
}

// find and return build of gate pipeline using build_id
// otherwise return false
def _get_build_by_id(build_no){
  if(! build_no.isInteger())
    return false
  def gate_pipeline = jenkins.model.Jenkins.instance.getItem(GATING_PIPELINE)
  def build = false
  gate_pipeline.getBuilds().any {
    println("DEBUG: check if ${it.getId().toInteger()} == ${build_no.toInteger()}")
    if (it.getId().toInteger() == build_no.toInteger()){
      build = it
      return true
    }
  }
  return build
}

// Function parse base chain and check if all builds is not failed
// if function meet successfully finished build in the chain, this
// build and all its base builds remove from the chain (chain shortened)
// Return true if NOT meet failure build and chain
// and false if meet some failures
def _check_base_chain_is_not_failed(base_chain){
  if(base_chain == "")
    return true
  def is_some_fails = false
  def arr_chain = base_chain.split(",")
  arr_chain.any { build_id ->
    def build = _get_build_by_id(build_id)
    if(build.getResult() == null) // is not finished yes - skip the build
      return false
    if(check_build_is_not_failed(build_id))
      return false
    else{
      is_some_fails = true
      return true
    }
  }
  return is_some_fails
}

// Function return ordered map with builds with data needed for find
// and process base build
def _prepare_builds_map(){
  def gate_pipeline = jenkins.model.Jenkins.instance.getItem(GATING_PIPELINE)
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

// function return true if project has contrail releases/branches structure
// otherwise return false
def is_normal_project(){
  return NORMAL_PROJECTS.contains(GERRIT_PROJECT)
}

// Function check if build's branch fit to current project branch
// Return true if we can use this build as a base build for current running pipeline
// Otherwise return false
def _is_branch_fit(build_id){
  def build = _get_build_by_id(build_id)

  println("DEBUG: check _is_branch_fit for build ${build}")

  if(is_normal_project()){
    // Project has contrail releases structure
    // Branch of the base build must be the same
    if(GERRIT_BRANCH != build.getEnvironment()['GERRIT_BRANCH'])
      return false
  }else{
    // Project has its own releases structure
    // Branch of the base build must be master
    if(build.getEnvironment()['GERRIT_BRANCH'] != 'master')
      return false
  }
  return true
}

// Function check build using build_no is failed
def check_build_is_not_failed(build_no){
  println("DEBUG: check build ${build_no} is failure")

  // Get the build
  def gate_pipeline = jenkins.model.Jenkins.instance.getItem(GATING_PIPELINE)
  def build = null

  gate_pipeline.getBuilds().any {
    println("DEBUG: check if ${it.getEnvVars().BUILD_ID.toInteger()} == ${build_no.toInteger()}")
    if (it.getEnvVars().BUILD_ID.toInteger() == build_no.toInteger()){
      build = it
      return true
    }
  }
  println("DEBUG: build for check found: ${build}")
  println("DEBUG: Result of build is ${build.getResult()}")
  if(build.getResult() != null){
      // Skip the build if it fails
      if(_gate_get_build_state(build) == 'FAILURE'){
        println ("DEBUG: Build ${build} fails")
        return false
      }else{
        println ("DEBUG: Build ${build} is not fails")
      }
    }
  return true
}

// The function get build's artifacts, find there VERIFIED,
// and check if it is integer and more than 0 return SUCCESS
// and return FAILRUE in another case
// !!! Works only if build has been finished! Check getResult() before call this function
def _gate_get_build_state(build){
    def result = "FAILURE"
    println("DEBUG: Check build here: gate_get_build_state")
    def artifactManager =  build.getArtifactManager()
    if (artifactManager.root().isDirectory()) {
      println("DEBUG: Artifact directory found")
      def fileList = artifactManager.root().list()
      println("DUBUG: filelist = ${fileList}")
      fileList.each {
        def file = it
        println("DEBUG: found file: ${file}")
        if(file.toString().contains('global.env')) {
          // extract global.env artifact for each build if exists
          def fileText = it.open().getText()
          println("DEBUG: content of global.env is : ${fileText}")
          fileText.split("\n").each {
            def line = it
            if(line.contains('VERIFIED')) {
              println("DEBUG: found VERIFIED line is ${line}")
              def verified = line.split('=')[1].trim()
              if(verified.isInteger() && verified.toInteger() > 0)
                result = "SUCCESS"
            }
          }
        }
      }
    }else{
      println("DEBUG: Not found artifact directory - suppose build fails")
    }
  println("DEBUG: Build is ${result}")
  return result
}

// Function find the build with build_no and wait it finishes with any result
def wait_pipeline_finished(build_no){
  waitUntil {
    def res = _get_pipeline_result(build_no)
    println("DEBUG: waitUntil get_pipeline_result is ${res}")
    return res
  }
}

// Put all this staff in separate function due to Serialisation under waitUntil
def _get_pipeline_result(build_no){
  def job = jenkins.model.Jenkins.instance.getItem(GATING_PIPELINE)
    // Get DEVENVTAG for build_no pipeline
    def build = null
    job.builds.any {
      if(build_no.toInteger() == it.getEnvVars().BUILD_ID.toInteger()){
        build = it
      }
    }
    return build.getResult() == null
}

// Check if pipeline with the same GERRIT_PROJECT is running
// and if it is then wait until finishes
def wait_until_project_pipeline(){
  def builds_map = _prepare_builds_map()
  def same_project_build = false
  builds_map.any { build_id, build_map ->
    if(build_map['project'] == GERRIT_PROJECT && build_map['status'] == 'null'){
      same_project_build = build_id
      return true
    }
  }

  if(same_project_build){
    waitUntil {
      build = _get_build_by_id(same_project_build)
      return ! (build.getResult() == null)
    }
  }
}

// function read patchset_info artiface from base build if exists
// read pachset_info of current build
// union all patchset_info in one array
// and write all info to patchset_info artifact of corrent build
def save_pachset_info(base_build_no){
  if(!(base_build_no && base_build_no.isInteger()))
    return

  def base_json = _get_base_patchset_info_json(base_build_no)

  def res_json = get_result_patchset(base_build_no)
  println("DEBUG: Return patchset info is ${res_json}")
  //sh """#!/bin/bash -e
  //  cat <<EOF > patchsets-info.json
  //  ${json_result_patchset_info}
  //  EOF
  //"""
  // writeFile(file: 'patchsets-info.json', text: json_result_patchset_info)
  println("DEBUG: Successfully saved patchset info")
  //archiveArtifacts(artifacts: "patchsets-info.json")
}

// all JSON calsulate to separate function
def get_result_patchset(base_build_no){
  println("DEBUG: start save_pachset_info")
  def new_patchset_info_text = readFile("patchsets-info.json")
  println("DEBUG: read text from file: ${new_patchset_info_text}")
  def sl = new JsonSlurper()
  def new_patchset_info = sl.parseText(new_patchset_info_text)
  println("DEBUG: parsed first JSON: ${new_patchset_info}")

  return true
  def base_patchset_info = ""

  println("DEBUG: Get patchset info from build ${base_build_no} before save")

  base_build = _get_build_by_id(base_build_no)
  def artifactManager =  base_build.getArtifactManager()
  if (artifactManager.root().isDirectory()) {
    def fileList = artifactManager.root().list()
    fileList.any {
      def file = it
      if(file.toString().contains('patchsets-info.json')) {
        // extract global.env artifact for each build if exists
        base_patchset_info = it.open().getText()
        return true
      }
    }
  }
  println("DEBUG: Found base patchset info in old build is ${base_patchset_info}")

  def sl2 = new JsonSlurper()
  println("DEBUG: JSON Slurper created")
  def old_patchset_info = sl2.parseText(base_patchset_info)
  println("DEBUG: JSON has been parsed : ${old_patchset_info}")
  if( old_patchset_info instanceof java.util.ArrayList ){
    println("DEBUG: old_patchset_info is instance of java.util.ArrayList")
    // If something looks like array found in patchset info of base build
    // Read current patchset and parse JSON
    println("DEBUG: We can parse current patchset info ${new_patchset_info}")
    def result_patchset_info = old_patchset_info + new_patchset_info
    println("DEBUG: Result patchset info before save is ${result_patchset_info}")
    def json_result_patchset_info = JsonOutput.toJson(result_patchset_info)
    println("DEBUG: JSON text = ${json_result_patchset_info}  class is ${json_result_patchset_info.class}")
    return json_result_patchset_info
  }

  return false

}

// Function extract patchset_info text from base build
def _get_base_patchset_info_json(base_build_no){
  def base_patchset_info = ""

  println("DEBUG: Get patchset info from build ${base_build_no} before save")
  return true
  base_build = _get_build_by_id(base_build_no)
  def artifactManager =  base_build.getArtifactManager()
  if (artifactManager.root().isDirectory()) {
    def fileList = artifactManager.root().list()
    fileList.any {
      def file = it
      if(file.toString().contains('patchsets-info.json')) {
        // extract global.env artifact for each build if exists
        base_patchset_info = it.open().getText()
        return true
      }
    }
  }
  println("DEBUG: Found base patchset info in old build is ${base_patchset_info}")
}

return this