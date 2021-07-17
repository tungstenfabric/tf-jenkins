# TF CI setup

CI is based on idea that just one Jenkins master is used for all regions, one slave and satellite infra nodes for each region. All jenkins jobs are run on some jenkins slave and create additional workers in the cloud when required.

## DNS settings

User has to configure DNS somewhere to address CI resources. All services use some common domain - we call it CI_DOMAIN. Also each service is placed in a region. Jenkins and monitoring may have simpler name due to one replica.
Required names:

- tf-jenkins.some_region.tungsten.io and tf-jenkins.tungsten.io with public IP
- tf-monitoring.some_region.tungsten.io and tf-monitoring.tungsten.io with public IP (same to tf-jenkins)
- tf-mirrors.some_region.tungsten.io with private IP
- tf-nexus.some_region.tungsten.io with public IP
- tf-aquascan.some_region.tungsten.io with private IP
- slave-1.some_region.tungsten.io with public IP

## VM-s creation

For now fully worked setup was made on vexxhost OpenStack provider and below steps are related to OpenStack specific. But similar setup was brought up in AWS and it's also work but with some bugs.

CI uses one VM for Jenkins master (monitoring also is placed on that machine) for any number of regions.
CI uses 4 VM-s in each region: on VM for Jenkins's slave, one VM for Nexus and logs storage, one VM for mirrors storage, one VM for Aquascan service.
Different VM for mirrors is used instead of adding same objects to Nexus. Such decision was made due to various bugs in Nexus and inabilities to implement some CI patterns (like staging).

CI uses two networks: first named as 'management' with subnet 10.0.0.0/16, second named as 'data' with subnet 10.20.0.0/16 and allocation pool 10.20.0.2-10.20.100.255. 'management' network is connected to router which is connected to public (external) network. All VM-s are run in 'management' network, 'data' network is used only for CI checks.

VM-s specifications:
Jenkins master and monitoring - 16 Gb RAM, 4 CPU, 500 Gb root disk, public IP, Ubuntu 18.04.
Jenkins slave - 32 Gb RAM, 8 CPU, 500 Gb root disk, public IP, Ubuntu 18.04.
Nexus and logs storage - 16 Gb RAM, 4 CPU, one disk of 2 Tb for root disk and one disk of 2 Tb for '/var/lib/docker' path, public IP, Ubuntu 18.04.
Mirrors VM - 16 Gb RAM, 4 CPU, 200 Gb root disk and 2 Tb for '/var/local/mirror' path, no public IP, Centos 7.
Aquascan VM - 8 Gb RAM, 2 CPU, 100 Gb root disk, no public IP, Centos 7.
All VM-s are created with one SSH keys - this key should be registered in the cloud.

## Deploy CI

If several regions should be deployed then it's better to deploy regions separately. It's possible to redeploy Jenkins master to add new slave but it's safer to add new slave via Jenkins GUI.

To deploy you need any machine which has access to all hosts in the setup. Jenkins master can be chosen to simplify deploy.
Do ssh into this machine and install required software:

```bash
sudo apt-get update -y
sudo apt-get install -y python3-pip git
sudo pip3 install --upgrade pip3
sudo pip3 install "ansible<2.10"
```

Then clone setup source code

```bash
git clone https://github.com/tungstenfabric/tf-jenkins
cd tf-jenkins/setup
```

Check hosts.yaml.example and create hosts.yaml for your deployment. If some creds can't be provided at this step then they can be added later via Jenkins UI.

Prepare various ssh keys

```bash
ansible-playbook -i hosts.yaml playbooks/generate-keys.yaml
```

After generation ssh keys you can overwrite them with previous keys in $HOME/tfci/ssh/ folder

Deploy mirrors, nexus, logserver

```bash
ansible-playbook -i hosts.yaml playbooks/deploy-mirrors.yaml
ansible-playbook -i hosts.yaml playbooks/deploy-nexus.yaml
ansible-playbook -i hosts.yaml playbooks/deploy-logserver.yaml
ansible-playbook -i hosts.yaml playbooks/deploy-merger-monitor.yaml
```

Deploy jenkins slave and master

```bash
ansible-playbook -i hosts.yaml playbooks/deploy-jenkins-slave.yaml
ansible-playbook -i hosts.yaml playbooks/deploy-jenkins-master.yaml
ansible-playbook -i hosts.yaml playbooks/deploy-mailrelay.yaml
```

Deploy monitoring

```bash
ansible-playbook -i hosts.yaml playbooks/deploy-monitoring.yaml
```

Deploy aquasec service

```bash
TODO
```

All playbooks are idempotent and can be re-run. Just note that jenkins-master playbook can rewrite some settings that were changed via UI.

Playbook jenkins-master creates all jobs by defult.

At this point Jenkins has just one user which is defined in hosts.yaml. Please create more users if required.
TODO: switch to some LDAP/SSO authorization.

## First time configuration

Infra must be initiallised to be able to run CI and infra checks/jobs. Please next steps in the same order.

- Set in UI/Configuration/Global Security/Markup Formatter to safeHTML (TODO: automate it)
- Run job **update-caches** for all items in dropdown one by one. This will upload to CI caches some predefined yum packages, third-party cache, VM images for sanity tests, and other similar objects.
- Run job **update-base-images** for ALL. This will download and register in the cloud base images for CI workers. Redhat images (for rhel7 and rhel8) should be downloaded with appropriate subscription and registered manually to be ablle to run Redhat related checks. Here is a CLI command to register image `openstack image create --container-format bare --disk-format qcow2 --file rhel7.qcow --tag rhel7 --shared base-rhel7-202102100000`. Name and tag must be in exaclt this format. Numbers in name is a date of image in format YYYYMMDD0000.
- Run job **update-prepared-images** for CENTOS7, UBUNTU18, UBUNTU20. This will prepare base images for workers to speed up CI checks.
- Run job **update-tpc-source-repository**. This will compile and publish some yum packages to use them later in build Contrail process. These packages are changed rarely and should be pre-build.
- Run job **pipeline-init-repos** for CENTOS7, UBUNTU18, UBUNTU20, RHEL7, RHEL8. These jobs may take several hours and can be run in parallel.
- Run job **update-prepared-images** for RHEL7, RHEL8

After this point CI should be ready to run checks. For ensure that all steps were made correctly plelase run job **pipline-nightly** and check results.

### Red Hat settings

To update Red Hat mirrors you have to set 'rhel_user', 'rhel_password', 'rhel_pool_id' variables in hosts.yaml. They will be passed to mirror's script and used during repos staging. To obtain pool id please list available pools and choose pool with words in name 'Red Hat OpenStack Platform', 'Available' key with 'Unlimited', 'Service Level' with 'Self-Support' and 'Entitlement Type' Virtual'. In most cases it willl be just one pool. Otherwise please use with longer 'End Date'.

```bash
subscription-manager register --name=rhel7repomirror --username=$RHEL_USER --password=$RHEL_PASSWORD
subscription-manager list --available
subscription-manager unregister
```

## Gerrit integration

To listen gerrit events and run CI checks some gerrit item should be registered in gerrit plugin via Jenkins configuration in UI. SSH keyfile is placed inside jenkins container at /var/jenkins_home/.ssh/${GERRIT_USER_NAME}_id_rsa
