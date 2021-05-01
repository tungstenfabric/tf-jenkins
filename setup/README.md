# Install CI infra per region. Do not try to deploy it to more than one region at once

1. Create hosts.yaml, see host.yaml.example.
1. Deploy nameservers

```bash
ansible-playbook -i hosts.yaml playbooks/deploy-nameservers.yaml
```

1. Set new nameservers as default ones for the networks.

1. Prepare various ssh keys

```bash
ansible-playbook -i hosts.yaml playbooks/generate-keys.yaml
```

1. Deploy mirrors, nexus, logserver

```bash
ansible-playbook -i hosts.yaml \
      playbooks/deploy-mirrors.yaml \
      playbooks/deploy-nexus.yaml \
      playbooks/deploy-logserver.yaml
```

1. Deploy Jenkins

```bash
ansible-playbook -i hosts.yaml playbooks/deploy-jenkins-slave.yaml playbooks/deploy-jenkins-master.yaml
```

1. Deploy monitoring

```bash
ansible-playbook -i hosts.yaml playbooks/deploy-monitoring.yaml
```

TODO: deploy aquasec on top
