def get_templates_jobs(template_names) {
  def data      = _get_data()
  def templates = _resolve_templates(data)

  def streams   = [:]
  def jobs      = [:]
  def post_jobs = [:]
  _add_templates_jobs(template_names, templates, streams, jobs, post_jobs)

  // Set empty dict for dicts without params
  _set_default_values(streams)
  _set_default_values(jobs)
  _set_default_values(post_jobs)
  // Do some checks
  // Check if all deps point to real jobs
  _check_dependencies(jobs)
  _check_dependencies(post_jobs)

  return [streams, jobs, post_jobs]
}



def get_project_jobs(project_name, gerrit_pipeline, gerrit_branch) {
  // get data
  def data = _get_data()

  // get templates
  def templates = _resolve_templates(data)

  // find project and pipeline inside it
  project = null
  for (item in data) {
    if (!item.containsKey('project') || item.get('project').name != project_name)
      continue
    if (item.get('project').containsKey('branch') && item.get('project').get('branch') != gerrit_branch) {
      continue
    }
    project = item.get('project')
    break
  }
  // fill jobs from project and templates
  def streams = [:]
  def jobs = [:]
  def post_jobs = [:]
  if (!project) {
    println("INFO: project ${project_name} is not defined in config")
    return [streams, jobs, post_jobs]
  }
  if (!project.containsKey(gerrit_pipeline)) {
    print("WARNING: project ${project_name} doesn't define pipeline ${gerrit_pipeline}")
    return [streams, jobs, post_jobs]
  }
  if (project[gerrit_pipeline].containsKey('templates')) {
    _add_templates_jobs(project[gerrit_pipeline].templates, templates, streams, jobs, post_jobs)
  }
  // merge info from templates with project's jobs
  _update_map(streams, project[gerrit_pipeline].get('streams', [:]))
  _update_map(jobs, project[gerrit_pipeline].get('jobs', [:]))
  _update_map(post_jobs, project[gerrit_pipeline].get('post-jobs', [:]))

  // set empty dict for dicts without params
  _set_default_values(streams)
  _set_default_values(jobs)
  _set_default_values(post_jobs)
  // do some checks
  // check if all deps point to real jobs
  _check_dependencies(jobs)
  _check_dependencies(post_jobs)

  return [streams, jobs, post_jobs]
}

def _get_data() {
  // read main file
  def data = readYaml(file: "${WORKSPACE}/src/tungstenfabric/tf-jenkins/config/projects.yaml")
  // read includes
  def include_data = []
  for (item in data) {
    if (item.containsKey('include')) {
      for (file in item['include']) {
        include_data += readYaml(file: "${WORKSPACE}/src/tungstenfabric/tf-jenkins/config/${file}")
      }
    }
  }
  data += include_data
  return data
}

def _add_templates_jobs(template_names, templates, streams, jobs, post_jobs) {
  for (template_name in template_names) {
    if (!templates.containsKey(template_name)) {
      throw new Exception("ERROR: template ${template_name} is absent in configuration")
    }
    template = templates[template_name]
    _update_map(streams,   template.get('streams',   [:]))
    _update_map(jobs,      template.get('jobs',      [:]))
    _update_map(post_jobs, template.get('post-jobs', [:]))
  }
}

def _set_default_values(def items) {
  for (def item in items.keySet()) {
    if (items[item] == null)
      items[item] = [:]
  }
}

def _check_dependencies(def jobs) {
  for (def item in jobs) {
    def deps = item.value.get('depends-on')
    if (deps == null || deps.size() == 0)
      continue
    for (def dep in deps) {
      def dep_name = dep instanceof String ? dep : dep.keySet().toArray()[0]
      if (!jobs.containsKey(dep_name))
        throw new Exception("Item ${item.key} has unknown dependency ${dep_name}")
    }
  }
}

def _resolve_templates(def config_data) {
  def templates = [:]
  for (def item in config_data) {
    if (item.containsKey('template')) {
      def template = item['template']
      if (!template.containsKey('streams'))
        template['streams'] = [:]
      if (!template.containsKey('jobs'))
        template['jobs'] = [:]
      if (!template.containsKey('post-jobs'))
        template['post-jobs'] = [:]
      templates[template.name] = template
    }
  }
  // resolve parent templates
  while (true) {
    def parents_found = false
    def parents_resolved = false
    for (def item in templates) {
      if (!item.value.containsKey('parents'))
        continue
      parents_found = true
      def new_parents = []
      for (def parent in item.value['parents']) {
        if (!templates.containsKey(parent))
          throw new Exception("ERROR: Unknown parent: ${parent}")
        if (templates[parent].containsKey('parents')) {
          new_parents += parent
          continue
        }
        parents_resolved = true
        item.value['streams'] += templates[parent]['streams']
        item.value['jobs'] += templates[parent]['jobs']
        item.value['post-jobs'] += templates[parent]['post-jobs']
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
  return templates
}

def _update_map(items, new_items) {
  for (item in new_items) {
    if (item.getClass() != java.util.LinkedHashMap$Entry) {
      throw new Exception("Invalid item in config - '${item}'. It must be an entry of HashMap")
    }
    def value = item.value != null ? item.value : [:]
    if (!items.containsKey(item.key))
      items[item.key] = value
    else
      items[item.key] += value
  }
}

return this
