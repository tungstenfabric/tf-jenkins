**New deployment (can be used for recovery)**

1. Populate hosts.yml as shown in the example hosts.yml.example
2. Run:
   ```
    ansible-playbook -i hosts.yml jenkins-slave.yml`
    ```
    Optional:
   ```
     -e  "apt_upgrade_all=true"           # Upgrade all packages 
     --private-key=/home/master/.ssh/plab # Deployment key
   ```
   *Note: The keypairs for the connection of master and slaves will be created in the directory playbook_dir*
1. Run:

   ```
   ansible-playbook -i hosts.yml jenkins-master.yml  -e "jenkins_new_deploy=true" -e 'jenkins_defaut_user_password=<StrongPassword>'
   ```

   Optional:

   ```
     -e  "jenkins_default_user=UserName"  # Deafault: self-jenkins
     -e  "apt_upgrade_all=true"           # Upgrade all packages 
     --private-key=/home/master/.ssh/plab # Deployment key
   ```
