Install CI infra per region. Do not try to deploy it to more than one region at once.

1. Create hosts.yaml, see host.yaml.example.
2. Deploy nameservers
   ```
   ansible-playbook -i hosts.yaml playbooks/deploy-nameservers.yaml
   ```
3. Set new nameservers as default ones for the networks.
4. Prepare logserver keys
   ```
   ansible-playbook -i hosts.yaml playbooks/generate-keys.yaml
   ```
5. Deploy mirrors, nexus, logserver
   ```
   ansible-playbook -i hosts.yaml \
       playbooks/deploy-mirrors.yaml \
       playbooks/deploy-nexus.yaml \
       playbooks/deploy-logserver.yaml
   ```
6. Deploy Jenkins
   ```
   ansible=playbook -i hosts.yaml \
     playbooks/jenkins-slave.yaml \
     playbooks/jenkins-master.yaml 
   ```
7. Deploy monitoring
   ```
   ansible-playbook -i hosts.yaml playbooks/deploy-monitoring.yaml
   ```

TODO: deploy aquasec on top
