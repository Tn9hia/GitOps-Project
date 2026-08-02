# Makefile
# Convenience targets for common Ansible operations

.PHONY: ping deploy-prod deploy-staging lint check-prod

ping:
	ansible all -m ping -i inventories/prod/hosts.yml

check-prod:
	ansible-playbook site.yml -i inventories/prod/hosts.yml --check --diff

deploy-prod:
	ansible-playbook site.yml -i inventories/prod/hosts.yml

lint:
	ansible-lint playbooks/ roles/

prepare-vm:
	ansible-playbook site.yml -i inventories/prod/hosts.yml --tags prepare-vm

deploy-ntpsec:
	ansible-playbook site.yml -i inventories/prod/hosts.yml --limit ntp-servers --tags ntpsec

deploy-apt-repo:
	ansible-playbook site.yml -i inventories/prod/hosts.yml --limit apt-repo --tags apt-repo

deploy-gitlab:
	ansible-playbook site.yml -i inventories/prod/hosts.yml --limit gitlab --tags gitlab

deploy-ffrouting:
	ansible-playbook site.yml -i inventories/prod/hosts.yml --limit ffrouting --tags ffrouting

# ansible-playbook site.yaml --limit dns --tags dns --check --diff
# ansible-playbook site.yaml --limit dns --tags dns

# ansible-playbook site.yaml --limit squid --tags squid --check --diff
# ansible-playbook site.yaml --limit squid --tags squid

# ansible-playbook site.yaml --limit gitlab --tags gitlab --check --diff
# ansible-playbook site.yaml --limit gitlab --tags gitlab

# ansible-playbook site.yaml --limit haproxy --tags haproxy --check --diff
# ansible-playbook site.yaml --limit haproxy --tags haproxy

# ansible-playbook site.yaml --limit k8s_control_plane --tags k8s --check --diff
# ansible-playbook site.yaml --limit k8s_control_plane --tags k8s
# ansible-playbook site.yaml --limit k8s_worker --tags k8s --check --diff
# ansible-playbook site.yaml --limit k8s_worker --tags k8s
