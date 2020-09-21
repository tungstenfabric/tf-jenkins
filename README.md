# tf_jenkins
This is the preparation of the future readme. Now only some of the points of using the system are contained here.

## Running jobs
We provide the ability to run jobs to check your patchsets sent for review. A template is a sequence of jobs. You can see all possible templates in the `config/templates.yaml` file.

### Check
Each project is associated with several templates that are launched by default when a new patchset is loaded. You can see the list of projects and associated templates in the `config/projects.yaml` file.

To independently initiate the review of templates related to the current project, add a comment to your review
```
check
```

### Check templates
To start checking a specific template, add a comment to your review like
```
check template template-name
```
For a several specific templates
```
check templates name-1 name-2 name-3
```

### Stop jobs
It is possible to stop all jobs running for the current review. To do this, add a comment to your review
```
cancel
```
