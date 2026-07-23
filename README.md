# Air-Gap GitOps Lab

> **Mục tiêu:** Xây dựng hạ tầng production-like, hoàn toàn **air-gap**, áp dụng GitOps principles
> với Kubernetes, IaC, và observability stack đầy đủ — có thể triển khai trên **VMware vCloud Director**
> hoặc **OpenStack**.

Bài lab tập trung vào việc dựng một môi trường air-gap (kiểm soát toàn bộ outbound traffic) chứ không
gắn cứng vào một nền tảng ảo hóa cụ thể. Phần provisioning được tách thành hai bộ Terraform độc lập,
dùng chung một bộ Ansible / ArgoCD / manifests phía sau:

| Thư mục | Nền tảng | Trạng thái |
|---|---|---|
| `terraform-vmware/` | VMware vCloud Director (NSX-T) | Đã hoàn thành |
| `terraform-openstack/` | OpenStack | Đang thực hiện |

---

## Đặc điểm hạ tầng

| Thuộc tính | Giá trị |
|---|---|
| Nền tảng | VMware vCloud Director **hoặc** OpenStack |
| Network model | Air-gap (kiểm soát toàn bộ outbound traffic) |
| Outbound access | Qua Squid Proxy (whitelist-based) |
| Deployment model | GitOps — Git is single source of truth |
| IaC | Terraform (provisioning) + Ansible (configuration) |
| CD Engine | ArgoCD |
| OS | Ubuntu 24.04 |

---

## Mô hình air-gap

Ý tưởng chung không phụ thuộc nền tảng: toàn bộ VM nằm trên một **internal network** không có route
trực tiếp ra internet. Chỉ có Squid Proxy là điểm duy nhất được phép ra ngoài (qua một **external /
routed network**), và mọi outbound HTTP/HTTPS đều phải đi qua Squid theo whitelist.

```
        Internal Network (air-gap)                External / Routed Network
  ┌──────────────────────────────────┐        ┌─────────────────────────────┐
  │                                  │        │                             │
  │  PowerDNS   NTPSec   apt-mirror  │        │                             │
  │  GitLab     Harbor   Vault       │        │        Edge / Router        │
  │  HAProxy    K8s nodes            │        │      (SNAT → Internet)       │
  │                                  │        │                             │
  │        Squid Proxy ──────────────┼────────┤        Squid Proxy          │
  │        (internal NIC)            │        │        (external NIC)        │
  │             ▲                    │        │                             │
  └─────────────┼────────────────────┘        └─────────────────────────────┘
                │
        HTTP/HTTPS proxy (port 3128)
```

Squid là VM duy nhất có NIC trên cả hai network. Các VM còn lại chỉ nằm trên internal network và truy
cập internet thông qua Squid proxy (HTTP/HTTPS). Riêng NTP sync traffic (UDP 123) đi thẳng qua routed
network — không qua Squid vì Squid chỉ xử lý HTTP/HTTPS.

### Quy hoạch network theo nền tảng

| Vai trò | VMware vCloud Director | OpenStack |
|---|---|---|
| Internal (air-gap) | `Isolated-Network` — `172.16.10.0/24`, gw `172.16.10.254` | `172.29.25.0/24` (services) + `172.29.27.0/24` (k8s) *(xem `.idea/openstack/planning.md`)* |
| External / Routed | `Routed-Network` — `192.168.100.0/24`, gw `192.168.100.254` | External network + floating IP |

> Chi tiết quy hoạch IP / domain / VM specs để điền trước khi làm lab:
> [`.idea/vmware/planning.md`](.idea/vmware/planning.md) và [`.idea/openstack/planning.md`](.idea/openstack/planning.md).

---

## Kiến trúc tổng quan

```
┌─────────────────────────────────────────────────────────────────────────┐
│              Virtualization Platform (VMware vCloud / OpenStack)        │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    Air-Gap Internal Network                      │   │
│  │                                                                  │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌──────────────────────┐  │   │
│  │  │  Squid Proxy│    │  PowerDNS   │    │       NTPSec         │  │   │
│  │  │ (outbound   │    │ (internal   │    │  (time sync)         │  │   │
│  │  │  control)   │    │  DNS)       │    │                      │  │   │
│  │  └─────────────┘    └─────────────┘    └──────────────────────┘  │   │
│  │                                                                  │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌──────────────────────┐  │   │
│  │  │    aptly    │    │   Vault     │    │       GitLab         │  │   │
│  │  │ (apt mirror)│    │ (PKI/Secret │    │  + GitLab Runner     │  │   │
│  │  │             │    │  /SSH CA)   │    │                      │  │   │
│  │  └─────────────┘    └─────────────┘    └──────────────────────┘  │   │
│  │                                                                  │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌──────────────────────┐  │   │
│  │  │   Harbor    │    │  Atlantis   │    │      Teleport        │  │   │
│  │  │  (registry) │    │ (Terraform  │    │  (access mgmt)       │  │   │
│  │  │             │    │  GitOps)    │    │                      │  │   │
│  │  └─────────────┘    └─────────────┘    └──────────────────────┘  │   │
│  │                                                                  │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │              Kubernetes Cluster                            │  │   │
│  │  │                                                            │  │   │
│  │  │   Control Plane (x3)      Worker Nodes (x3)                │  │   │
│  │  │   ┌──────────────┐        ┌───────────────────────────┐    │  │   │
│  │  │   │ kube-apiserver│        │  ArgoCD  │  Workloads    │    │  │   │
│  │  │   │ etcd          │        │  Traefik │  Prometheus   │    │  │   │
│  │  │   │ scheduler     │        │  Grafana │  Loki         │    │  │   │
│  │  │   └──────────────┘        └───────────────────────────┘    │  │   │
│  │  │                                                            │  │   │
│  │  │   CNI: Cilium   │   CSI: Longhorn   │   LB: HAProxy        │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                        ▲                                │
│                              Internet (controlled via Squid)            │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Thành phần hệ thống

### Network & Access Control

| Component | Role | Notes |
|---|---|---|
| **Squid Proxy** | Kiểm soát outbound traffic | Whitelist-based ACL, logging đầy đủ |
| **PowerDNS** | Internal DNS resolution | Authoritative + Recursor, split-horizon |
| **NTPSec** | Time synchronization | Internal stratum, sync từ upstream qua proxy |
| **Teleport** | Privileged access management | SSH, K8s access, session recording, audit log |

### Package & Image Management

| Component | Role | Notes |
|---|---|---|
| **aptly** | APT package mirror | Kiểm soát version, offline install cho Ubuntu/Debian |
| **Harbor** | Private container registry | Trivy scanning, Cosign signing, RBAC, replication |

### Secret & PKI

| Component | Role | Notes |
|---|---|---|
| **HashiCorp Vault** | PKI CA, Secret management, SSH CA | Issue TLS cert cho internal services, SSH cert signing |

### Source Control & CI

| Component | Role | Notes |
|---|---|---|
| **GitLab** | Source control, CI platform | Tập trung toàn bộ code, config, manifest |
| **GitLab Runner** | CI job executor | Build image, run test, push lên Harbor |

### Infrastructure as Code

| Component | Role | Notes |
|---|---|---|
| **Terraform** | Infrastructure provisioning | Hai bộ riêng: `terraform-vmware/` (vCloud) và `terraform-openstack/` |
| **Atlantis** | GitOps cho Terraform | Plan on PR, Apply on merge, state locking |
| **Ansible** | Configuration management | Cấu hình OS, deploy non-K8s services |

### Kubernetes Platform

| Component | Role | Notes |
|---|---|---|
| **Cluster** | 3 control plane + 3 worker | HA setup |
| **Cilium** | CNI | eBPF-based networking, Network Policy, thay thế kube-proxy |
| **Longhorn** | CSI Storage | Distributed block storage, snapshot, backup |
| **Traefik** | Ingress Controller | Routing, TLS termination (cert từ Vault PKI) |
| **HAProxy** | External Load Balancer | L4/L7 LB cho service expose ra ngoài cluster |

### GitOps & CD

| Component | Role | Notes |
|---|---|---|
| **ArgoCD** | Continuous Delivery | Pull-based, sync từ GitLab manifest repo, drift detection |

### Observability

| Component | Role | Notes |
|---|---|---|
| **Prometheus** | Metrics collection | kube-state-metrics, node-exporter, app metrics |
| **Grafana** | Visualization & Alerting | Dashboard cho infra + app |
| **Loki** | Log aggregation | Log từ K8s pods + system logs |

---

## CI/CD Flow

```
Developer
    │
    ▼
GitLab (push code / open MR)
    │
    ├──► GitLab Runner ──► Build image ──► Push to Harbor
    │                                            │
    │                                            ▼
    │                                    Update image tag
    │                                    trong manifest repo
    │
    ├──► Atlantis (nếu thay đổi Terraform)
    │       │
    │       ├── terraform plan  (on MR)
    │       └── terraform apply (on merge)
    │
    ▼
ArgoCD (watch manifest repo)
    │
    └──► Sync to Kubernetes Cluster
              │
              └──► Deploy workloads
```

---

## Access Flow (Air-Gap)

```
Engineer
    │
    │ (VPN → internal network)
    ▼
Teleport Proxy
    │
    ├── SSH vào servers (cert từ Vault SSH CA, TTL-based)
    ├── kubectl access vào K8s (Teleport K8s integration)
    └── Audit log toàn bộ session
```

---

## Repository Structure

```
GitOps/
├── terraform-vmware/           # Provisioning trên VMware vCloud Director (done)
│   ├── main.tf                 # Networks + VM modules
│   ├── provider.tf             # vcd provider + GitLab http backend
│   ├── modules/vapp/           # Module tạo vApp/VM
│   └── README.md
│
├── terraform-openstack/        # Provisioning trên OpenStack (in progress)
│   ├── main.tf
│   ├── provider.tf             # openstack provider
│   └── modules/instance/
│
├── ansible/                    # Configuration management (dùng chung)
│   ├── inventories/
│   │   ├── prod/
│   │   └── uat/
│   ├── roles/                  # squid, powerdns, ntpsec, gitlab, haproxy, k8s...
│   ├── playbooks/
│   └── site.yaml
│
├── argocd/                     # GitOps CD — apps, charts, helm-values, kustomize
│   ├── apps/                   # cilium, longhorn, traefik...
│   ├── bootstrap/              # root-app (app-of-apps)
│   └── helm-values/
│
├── docs/                       # Documentation & diagrams
│   └── docs/diagrams/          # D2lang diagram sources
│
└── .idea/                      # Planning cho bài lab (tách theo nền tảng)
    ├── vmware/
    │   └── planning.md         # Quy hoạch IP / domain / VM specs — VMware
    └── openstack/
        ├── planning.md         # Quy hoạch IP / domain / VM specs — OpenStack
        └── master-plan.md      # Working notes & task tracking
```

---

## Deployment Phases

### Phase 0 — Planning
- [ ] Chọn nền tảng: `terraform-vmware/` hoặc `terraform-openstack/`
- [ ] Điền quy hoạch IP / domain / network / VM specs trong `.idea/vmware/planning.md` hoặc `.idea/openstack/planning.md`

### Phase 1 — Foundation (Basic Services)
- [ ] Provision VMs với Terraform (VMware hoặc OpenStack)
- [ ] Cấu hình Squid Proxy (outbound control)
- [ ] Deploy PowerDNS (internal DNS)
- [ ] Deploy NTPSec (time sync)
- [ ] Setup aptly (package mirror)

### Phase 2 — Platform Core
- [ ] Deploy HashiCorp Vault (PKI + SSH CA + Secret)
- [ ] Deploy GitLab + GitLab Runner
- [ ] Deploy Harbor (private registry)
- [ ] Deploy Teleport (access management)

### Phase 3 — Kubernetes
- [ ] Provision K8s cluster (kubeadm)
- [ ] Install Cilium CNI
- [ ] Install Longhorn CSI
- [ ] Deploy Traefik Ingress + HAProxy LB
- [ ] TLS integration với Vault PKI

### Phase 4 — GitOps & IaC
- [ ] Setup Atlantis (Terraform GitOps)
- [ ] Deploy ArgoCD
- [ ] Cấu hình CI/CD pipeline (GitLab CI → Harbor → ArgoCD)
- [ ] Migrate Ansible roles vào GitLab

### Phase 5 — Observability
- [ ] Deploy Prometheus + node-exporter + kube-state-metrics
- [ ] Deploy Grafana (dashboards)
- [ ] Deploy Loki + log shipping
- [ ] Setup alerting rules

---

## Security Notes

- Toàn bộ TLS certificate được cấp bởi **Vault PKI CA** — không dùng self-signed
- SSH access quản lý qua **Vault SSH CA** + **Teleport** — không dùng static SSH key
- Container image phải qua **Harbor Trivy scan** trước khi deploy
- Network Policy mặc định **deny-all**, chỉ allow explicit
- Outbound traffic phải qua **Squid whitelist** — không có direct internet access
- Secrets không được commit vào Git — dùng **Vault** + External Secrets Operator

---

## Prerequisites

- Truy cập API của nền tảng đích:
  - VMware vCloud Director API access, **hoặc**
  - OpenStack API access (Keystone auth URL, tenant/project)
- Terraform >= 1.6
- Ansible >= 2.15
- kubectl, helm, helmfile
- VPN access vào internal network
- OS: Ubuntu 24.04

---

> **Note:**
> - Provisioning chi tiết theo nền tảng: [`terraform-vmware/README.md`](terraform-vmware/README.md) và `terraform-openstack/`.
> - Diagram chi tiết từng layer xem tại `docs/docs/diagrams/` (D2lang format).
