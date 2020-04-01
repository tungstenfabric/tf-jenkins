
// Constants
GATING_PIPELINE = 'pipeline-gate-opencontrail-c'

// Function find base build fits to be the base build
// get its base builds list if any, and then iterate over the list
// check if items of the list is still working or SUCCESS or FAILURE.
// If next build is fit to be a base build, the function add its id to BASE_BUILDS_LIST
// also prepare DEPS_LIST and these vars to global.env
// return false if base build not found or base build id in the other case
def save_base_builds(){
  return false
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
    return ! res
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