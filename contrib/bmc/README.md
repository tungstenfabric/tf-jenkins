#Deploying BMC cluster

1) Setup initial RHEL with ssh access on every kvm node
2) Edit inventory.yaml.example according your conditions and rename it to  inventory.yaml
3) Use ansible playbook for deployment

```
cd playbooks
ansible-playbook -i inventory.yaml deploy-kvm.yaml
```
# Use scripts bmc-cluster-tools for management


