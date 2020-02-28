**New deployment**

1. Populate hosts.yml as shown in the example hosts.yml.example
2. Run:
   ```
    ansible-playbook -i hosts.yml jenkins-slave.yml
    ```
    Optional:
   ```
     -e "apt_upgrade_all=true"           # Upgrade all packages 
     --private-key=$HOME/.ssh/plab # Deployment key
   ```
   *Note: The keypairs for the connection of master and slaves will be created in the directory playbook_dir*
3. Run:

   ```
   ansible-playbook -i hosts.yml jenkins-master.yml  -e "jenkins_new_deploy=true" -e 'jenkins_defaut_user_password=<StrongPassword>'
   ```

   Optional:

   ```
     -e "jenkins_default_user=UserName"         # Default: self-jenkins
     -e "jenkins_fqdn=jenkins.domain.tld        # Default: tf-jenkins.progmaticlab.com
     -e "jenkins_admin_email=jenkins@domain.tld # Default:null@progmaticlab.com"
     -e "apt_upgrade_all=true"                  # Upgrade all packages 
     --private-key=/home/master/.ssh/plab       # Deployment key
   ```


**Upgrade**

Upgrading deployment to the latest container version jenkins/jenkins:lts

Run:
   ```
   ansible-playbook -i hosts.yml jenkins-master.yml
   ```

**Recovery**

1. Complete all the steps in the "New deployment" section.
2. TBC
