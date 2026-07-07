# Makefile
# Convenience targets for common Ansible operations

.PHONY: ping deploy-prod deploy-staging lint check-prod

ping:
  ansible all -m ping -i inventories/production/hosts.yml

deploy-prod:
  ansible-playbook playbooks/site.yml -i inventories/production/hosts.yml

lint:
  ansible-lint playbooks/ roles/

check-prod:
  ansible-playbook playbooks/site.yml -i inventories/production/hosts.yml --check --diff

  # dry-run trước
ansible-playbook site.yaml --limit ntp --tags prepare-vm --check --diff
# chạy thật
# ansible-playbook site.yaml --limit ntp --tags prepare-vm
# ansible-playbook site.yaml --limit ntp --tags ntpsec --check --diff
# ansible-playbook site.yaml --limit ntp --tags ntpsec

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