# Ansible Project Structure — Air-Gap GitOps Lab

---

## Cấu trúc tổng quan

```
ansible/
├── ansible.cfg                         # Engine config: forks, roles_path, vault_password_file
├── requirements.yml                    # Galaxy collections & roles dependencies
├── site.yml                            # Master playbook — entry point duy nhất
│
├── inventory/                          # Danh sách máy + biến
│   ├── hosts.yml                       # Khai báo host & group theo phase
│   ├── group_vars/
│   │   ├── all/                        # Áp dụng cho MỌI host — single source of truth
│   │   │   ├── 00_main.yml             # Lab metadata, registry URL, apt mirror
│   │   │   ├── proxy.yml               # squid_host, proxy_url, no_proxy
│   │   │   ├── dns.yml                 # dns_servers[], search_domain
│   │   │   ├── ntp.yml                 # ntp_server, stratum
│   │   │   ├── network.yml             # Subnets, service IPs, K8s VIPs
│   │   │   ├── tls.yml                 # vault_addr, PKI mount, cert TTL
│   │   │   └── secrets.yml             # Ansible-vault encrypted passwords
│   │   ├── foundation/                 # Vars cho group: squid, powerdns, ntpsec, aptly
│   │   ├── platform/                   # Vars cho group: vault, gitlab, harbor, teleport
│   │   ├── kubernetes/                 # Vars cho group: k8s version, pod CIDR, CNI
│   │   ├── gitops/                     # Vars cho group: atlantis, argocd
│   │   └── observability/              # Vars cho group: prometheus, grafana, loki
│   └── host_vars/                      # Per-host override — ưu tiên cao hơn group_vars
│       ├── squid-01.yml                # Dual-NIC config, override proxy_url=""
│       ├── powerdns-01.yml
│       └── ...                         # 1 file / host
│
├── playbooks/                          # Kịch bản triển khai theo phase
│   ├── phase1-foundation/
│   │   ├── squid.yml
│   │   ├── powerdns.yml
│   │   ├── ntpsec.yml
│   │   └── aptly.yml
│   ├── phase2-platform/
│   │   ├── vault.yml
│   │   ├── gitlab.yml
│   │   ├── harbor.yml
│   │   └── teleport.yml
│   ├── phase3-kubernetes/
│   │   ├── k8s-preflight.yml           # sysctl, swap off, kernel modules
│   │   ├── k8s-cluster.yml
│   │   ├── cilium.yml
│   │   ├── longhorn.yml
│   │   ├── traefik.yml
│   │   └── haproxy.yml
│   ├── phase4-gitops/
│   │   ├── atlantis.yml
│   │   └── argocd.yml
│   └── phase5-observability/
│       ├── prometheus.yml
│       ├── grafana.yml
│       ├── loki.yml
│       └── alertmanager.yml
│
└── roles/                              # Logic cài đặt từng service
    ├── common/                         # Baseline — chạy đầu tiên trên MỌI host
    │   ├── tasks/
    │   │   ├── main.yml
    │   │   ├── proxy.yml               # /etc/environment, apt proxy
    │   │   ├── dns.yml                 # systemd-resolved config
    │   │   ├── ntp.yml                 # chrony config
    │   │   ├── ca_trust.yml            # Install internal CA bundle
    │   │   ├── sshd.yml                # Harden SSH
    │   │   ├── sysctl.yml              # Kernel parameters
    │   │   ├── ufw.yml                 # Baseline firewall deny-all
    │   │   └── users.yml               # Ops user, sudo, SSH key
    │   ├── handlers/
    │   ├── defaults/
    │   ├── templates/
    │   └── meta/
    ├── squid/                          # [P1] Outbound proxy
    ├── powerdns/                       # [P1] Internal DNS
    ├── ntpsec/                         # [P1] Time sync
    ├── aptly/                          # [P1] APT package mirror
    ├── vault/                          # [P2] PKI CA, SSH CA, Secret management
    ├── gitlab/                         # [P2] Source control & CI
    ├── harbor/                         # [P2] Container registry
    ├── teleport/                       # [P2] Privileged access management
    ├── kubernetes/                     # [P3] kubeadm init/join, kubeconfig
    ├── cilium/                         # [P3] CNI — eBPF networking
    ├── longhorn/                       # [P3] Distributed block storage
    ├── traefik/                        # [P3] Ingress controller
    ├── haproxy/                        # [P3] External load balancer
    ├── atlantis/                       # [P4] Terraform GitOps
    ├── argocd/                         # [P4] CD engine — bootstrap only
    ├── prometheus/                     # [P5] Metrics collection
    ├── grafana/                        # [P5] Visualization & alerting
    ├── loki/                           # [P5] Log aggregation
    └── alertmanager/                   # [P5] Alert routing
```

---

## Chú thích từng thành phần

### `ansible.cfg` — Engine config

Config chính của Ansible engine. Định nghĩa số luồng xử lý song song, đường dẫn roles, và file chứa vault password để decrypt secrets tự động khi chạy.

```ini
[defaults]
forks               = 10
roles_path          = roles
inventory           = inventory/hosts.yml
vault_password_file = ~/.vault_pass

[ssh_connection]
pipelining = True
ssh_args   = -o ControlMaster=auto -o ControlPersist=60s
```

> `pipelining=True` giảm số SSH connection cần thiết → tăng tốc độ đáng kể khi chạy trên nhiều host.

---

### `requirements.yml` — Galaxy dependencies

Khai báo Ansible Galaxy collections cần cài trước khi chạy. Trong môi trường air-gap phải mirror collections vào aptly hoặc bundle sẵn.

```yaml
collections:
  - name: community.general
    version: ">=8.0.0"
  - name: community.crypto
  - name: ansible.posix
```

> Air-gap: dùng `ansible-galaxy collection download` để tải offline, sau đó cài từ tarball local.

---

### `site.yml` — Master playbook

Điểm khởi đầu duy nhất. Orchestrate toàn bộ các phase theo thứ tự. Không chứa task cụ thể — chỉ import playbook con.

```yaml
---
- name: Apply common baseline to all hosts
  import_playbook: playbooks/phase1-foundation/common.yml

- name: Phase 1 — Foundation services
  import_playbook: playbooks/phase1-foundation/squid.yml

- name: Phase 2 — Platform core
  import_playbook: playbooks/phase2-platform/vault.yml
```

> Chạy từng phase: `ansible-playbook site.yml --tags phase1` hoặc `--limit foundation`

---

### `inventory/hosts.yml` — Khai báo host & group

Danh sách tất cả VM, phân nhóm theo phase. Group name phải khớp với thư mục `group_vars/<group>/`.

```yaml
all:
  children:
    foundation:
      hosts:
        squid-01:    { ansible_host: 172.16.10.12 }
        powerdns-01: { ansible_host: 172.16.10.10 }
        ntpsec-01:   { ansible_host: 172.16.10.15 }
    platform:
      hosts:
        vault-01:    { ansible_host: 172.16.10.20 }
        gitlab-01:   { ansible_host: 172.16.10.30 }
    kubernetes:
      children:
        k8s_control_plane:
          hosts:
            k8s-cp-01: { ansible_host: 172.16.10.60 }
            k8s-cp-02: { ansible_host: 172.16.10.61 }
            k8s-cp-03: { ansible_host: 172.16.10.62 }
        k8s_worker:
          hosts:
            k8s-wk-01: { ansible_host: 172.16.10.70 }
            k8s-wk-02: { ansible_host: 172.16.10.71 }
            k8s-wk-03: { ansible_host: 172.16.10.72 }
```

---

### `group_vars/all/` — Biến áp dụng cho MỌI host

Tách thành nhiều file theo concern — Ansible tự load toàn bộ. Đây là **single source of truth** cho infrastructure globals. Thay đổi ở đây, tất cả roles tự pick up.

#### Variable priority (thấp → cao)

```
group_vars/all/  →  group_vars/<group>/  →  host_vars/<host>
```

#### `proxy.yml`

```yaml
squid_host: "172.16.10.12"
squid_port: 3128
proxy_url:  "http://{{ squid_host }}:{{ squid_port }}"
no_proxy: >-
  localhost,127.0.0.1,172.16.10.0/24,.lab.internal

proxy_env:
  http_proxy:  "{{ proxy_url }}"
  https_proxy: "{{ proxy_url }}"
  no_proxy:    "{{ no_proxy }}"
```

#### `dns.yml`

```yaml
dns_servers:
  - "172.16.10.10"       # PowerDNS primary
dns_search_domain: "lab.internal"
dns_zone:          "lab.internal"
dns_forward_zones:
  ".": "9.9.9.9"         # upstream qua Squid
```

#### `ntp.yml`

```yaml
ntp_server:   "172.16.10.15"
ntp_stratum:  2
ntp_makestep: "1.0 3"
ntp_rtcsync:  true
ntp_fallback: []           # air-gap: không có external fallback
```

#### `network.yml`

```yaml
isolated_cidr: "172.16.10.0/24"
isolated_gw:   "172.16.10.254"
routed_cidr:   "192.168.100.0/24"
routed_gw:     "192.168.100.254"

# Service IPs — phải khớp Terraform output
squid_ip:    "172.16.10.12"
vault_ip:    "172.16.10.20"
gitlab_ip:   "172.16.10.30"
harbor_ip:   "172.16.10.40"
teleport_ip: "172.16.10.50"

# Kubernetes VIPs
k8s_api_vip:     "172.16.10.100"
k8s_ingress_vip: "172.16.10.101"
```

#### `tls.yml`

```yaml
vault_addr:      "https://vault.lab.internal:8200"
vault_pki_mount: "pki"
vault_pki_role:  "internal-services"
vault_ssh_mount: "ssh"

tls_cert_ttl: "720h"
tls_cert_dir: "/etc/ssl/lab"
tls_ca_cert:  "{{ tls_cert_dir }}/ca.crt"
internal_ca_bundle: "/usr/local/share/ca-certificates/lab-ca.crt"
```

#### `secrets.yml`

```yaml
# Tạo bằng: ansible-vault encrypt group_vars/all/secrets.yml
# Hoặc encrypt từng giá trị: ansible-vault encrypt_string 'value'

vault_root_token:      !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...encrypted...

gitlab_root_password:  !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...encrypted...

harbor_admin_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...encrypted...
```

> CI/CD: export `ANSIBLE_VAULT_PASSWORD_FILE` hoặc dùng `--vault-id @prompt` khi chạy thủ công.

---

### `inventory/host_vars/` — Per-host override

Override biến cho từng host cụ thể. Ưu tiên cao hơn group_vars. Dùng khi 1 host có config đặc biệt — ví dụ Squid có 2 NIC.

```yaml
# host_vars/squid-01.yml
ansible_host: 172.16.10.12

# Dual-homed interfaces
squid_isolated_iface: "ens192"   # 172.16.10.12
squid_routed_iface:   "ens224"   # 192.168.100.x
squid_routed_ip:      "192.168.100.12"

# Override: Squid không tự dùng chính nó làm proxy — tránh loop
proxy_url: ""
```

---

### `playbooks/` — Kịch bản triển khai theo phase

Mỗi playbook định nghĩa: chạy trên host group nào, áp dụng role nào, theo thứ tự nào.

```yaml
# Cấu trúc điển hình — ví dụ phase2/vault.yml
---
- name: Deploy HashiCorp Vault
  hosts: platform
  become: true
  roles:
    - common    # luôn luôn đầu tiên
    - vault
```

> `--check` để dry-run, `--diff` để xem thay đổi file trước khi apply.

---

### `roles/common/` — Baseline, chạy đầu tiên trên MỌI host

Role quan trọng nhất. Inject proxy, DNS, NTP, CA trust vào mọi máy. Các role khác assume `common` đã chạy xong.

```
tasks/
├── proxy.yml      # /etc/environment, apt proxy config
├── dns.yml        # systemd-resolved config
├── ntp.yml        # chrony config từ ntp_server var
├── ca_trust.yml   # install internal CA → update-ca-certificates
├── sshd.yml       # harden SSH: disable root, key-only
├── sysctl.yml     # kernel params: ip_forward, inotify...
├── ufw.yml        # baseline deny-all firewall
└── users.yml      # ops user, sudo, SSH key
```

> Thứ tự task quan trọng: `proxy` → `dns` → `ca_trust` → `ntp`. APT cần proxy để resolve, NTPSec dùng TLS nên cần CA trust trước.

---

### `roles/<service>/` — Logic cài đặt từng service

Mỗi role lo đúng 1 service. Không hardcode giá trị — chỉ đọc biến từ `defaults/` hoặc `group_vars`.

```
roles/<service>/
├── tasks/
│   ├── main.yml        # entry point
│   ├── install.yml     # cài package từ aptly mirror
│   ├── configure.yml   # render template → config file
│   └── service.yml     # start/enable systemd service
├── handlers/
│   └── main.yml        # restart service khi config thay đổi
├── defaults/
│   └── main.yml        # default vars — bị override bởi group_vars
├── templates/
│   └── *.j2            # Jinja2 config templates
└── meta/
    └── main.yml        # role dependencies
```

> `defaults/main.yml` là fallback. `group_vars/all/` có độ ưu tiên cao hơn và sẽ override.

---

## Luồng hoạt động

```
site.yml
  └─► import playbook theo phase
        └─► playbook chỉ định hosts + roles
              └─► roles đọc biến từ:
                    ├── group_vars/all/      # infrastructure globals
                    ├── group_vars/<group>/  # group-specific vars
                    └── host_vars/<host>     # per-host override
                  └─► render template → deploy config → start service
```

---

## Deployment phases

| Phase | Nội dung | Ghi chú |
|---|---|---|
| **P1 — Foundation** | Squid, PowerDNS, NTPSec, aptly | Phải xong trước tất cả |
| **P2 — Platform** | Vault, GitLab, Harbor, Teleport | Vault PKI phải up trước K8s |
| **P3 — Kubernetes** | Cluster, Cilium, Longhorn, Traefik, HAProxy | Cần Harbor để pull image |
| **P4 — GitOps** | Atlantis, ArgoCD | Cần GitLab + Harbor |
| **P5 — Observability** | Prometheus, Grafana, Loki, Alertmanager | Deploy sau khi K8s stable |