# Air-Gap GitOps Lab — VMware vCloud Director

> **Mục tiêu:** Xây dựng hạ tầng production-like, hoàn toàn air-gap trên VMware vCloud Director,
> áp dụng GitOps principles với Kubernetes, IaC, và observability stack đầy đủ.

---

## Đặc điểm hạ tầng

| Thuộc tính | Giá trị |
|---|---|
| Nền tảng | VMware vCloud Director |
| Network model | Air-gap (kiểm soát toàn bộ outbound traffic) |
| Outbound access | Qua Squid Proxy (whitelist-based) |
| Deployment model | GitOps — Git is single source of truth |
| IaC | Terraform (provisioning) + Ansible (configuration) |
| CD Engine | ArgoCD |

---

## Kiến trúc tổng quan

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        VMware vCloud Director                           │
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
| **Terraform** | Infrastructure provisioning | Tạo VM, network, storage trên vCloud Director |
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
    │ (VPN → vCloud network)
    ▼
Teleport Proxy
    │
    ├── SSH vào servers (cert từ Vault SSH CA, TTL-based)
    ├── kubectl access vào K8s (Teleport K8s integration)
    └── Audit log toàn bộ session
```

---

## Deployment Phases

### Phase 1 — Foundation (Basic Services)
- [x] Provision VMs với Terraform trên vCloud Director ✅ 2026-05-16
- [x] Cấu hình Squid Proxy (outbound control) ✅ 2026-05-16
- [x] Deploy PowerDNS (internal DNS) ✅ 2026-05-30
- [x] Deploy NTPSec (time sync) ✅ 2026-05-16
- [ ] Setup aptly (package mirror)

### Phase 2 — Platform Core
- [x] Deploy HashiCorp Vault (PKI + SSH CA + Secret) ✅ 2026-05-30
- [ ] Deploy GitLab + GitLab Runner
- [ ] Deploy Harbor (private registry)
- [ ] Deploy Teleport (access management)

### Phase 3 — Kubernetes
- [ ] Provision K8s cluster (kubeadm hoặc Terraform)
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

- VMware vCloud Director API access
- Terraform >= 1.6
- Ansible >= 2.15
- kubectl, helm, helmfile
- VPN access vào vCloud network
- OS: Ubuntu24.04
