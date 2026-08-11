# Makefile
# Convenience targets for common Ansible operations

.PHONY: ping deploy-prod deploy-staging lint check-prod

ping: # Check connection to all hosts
	ansible all -m ping -i inventories/prod/hosts.yml

check-prod: # Check playbook execution on prod
	ansible-playbook site.yml -i inventories/prod/hosts.yml --check --diff

deploy-prod: # Deploy playbook on prod
	ansible-playbook site.yml -i inventories/prod/hosts.yml

lint: # Lint playbooks and roles
	ansible-lint playbooks/ roles/

# Run playbook separately
deploy-squid: # Deploy Squid
	ansible-playbook site.yml -i inventories/prod/hosts.yml --limit squid --tags squid

prepare-vm: # Set up prerequisites for VM
	ansible-playbook site.yml -i inventories/prod/hosts.yml --tags prepare-vm

deploy-ntpsec: # Deploy NTPsec Server
	ansible-playbook site.yml -i inventories/prod/hosts.yml --limit ntp-servers --tags ntpsec

deploy-apt-repo: # Deploy APT repository
	ansible-playbook site.yml -i inventories/prod/hosts.yml --limit apt-repo --tags apt-repo

deploy-gitlab: # Deploy GitLab
	ansible-playbook site.yml -i inventories/prod/hosts.yml --limit gitlab --tags gitlab

deploy-ffrouting: # Deploy FF routing
	ansible-playbook site.yml -i inventories/prod/hosts.yml --limit ffrouting --tags ffrouting

prepare-k8s-node: # Prepare k8s node
	ansible-playbook site.yml -i inventories/prod/hosts.yml --limit k8s_control_plane --tags k8-prepare-node

init-k8s-cluster: # Initialize k8s cluster
	ansible-playbook site.yml -i inventories/prod/hosts.yml --limit k8s_control_plane --tags k8s-init-cluster

add-k8s-worker: # Add k8s worker
	ansible-playbook site.yml -i inventories/prod/hosts.yml --limit k8s_worker --tags k8s-add-worker

# ansible-playbook site.yaml --limit k8s_worker --tags k8s --check --diff
# ansible-playbook site.yaml --limit k8s_worker --tags k8s
