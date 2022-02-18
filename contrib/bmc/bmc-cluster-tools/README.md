# Tools for backup and restore VMs, generating instackenv.json and other



Lab configuration is described in file with env extension (for example rhosp16.1-full.env)

Lab configuration contains following details:
Virtual nodes:
  - kvm server for deploying VMs
  - port number for vbmc
  - pool for creating disk
  - names openstack hostname (for instackenv.json)
  
Baremetal nodes must be described in json files which will include into instackenv.json as they are.

 

LAB lifecycle

1) Lab created with create-lab.sh and can be used by Jenkins
2) Jenkins periodically redeploy lab with script reinit-lab.sh
3) Deployed lab can be saved with backup_VMs.sh and quickly restored with restore-lab-from-backup.sh (OPTIONAL).
4) Lab can be deleted with cleanup-lab.sh 

