# Terraform — VMware vCloud Director

Bộ Terraform provisioning hạ tầng air-gap cho bài **Air-Gap GitOps Lab** trên **VMware vCloud Director**
(NSX-T backend). Đây là một trong hai target IaC của project — target còn lại là `../terraform-openstack/`.
Xem tổng quan kiến trúc ở [`../README.md`](../README.md) và quy hoạch chi tiết ở [`../.idea/vmware/planning.md`](../.idea/vmware/planning.md).

> **Trạng thái:** đã hoàn thành.

---

## Nội dung

Bộ code này tạo ra:

- **2 network** trên vCloud Director:
  - `Isolated-Network` (air-gap internal) — backed by NSX-T, không có route ra ngoài.
  - `Routed-Network` — gắn với NSX-T Edge Gateway, có SNAT ra internet.
- Các **VM hạ tầng** dựng từ module `modules/vapp` (một vApp cho mỗi VM), NIC gắn manual IP.

Provider và backend khai báo trong `provider.tf`:

- Provider: `vmware/vcd` (dùng cho Viettel Cloud vCloud Director).
- Backend: **GitLab-managed Terraform state** (`backend "http"`) — state + lock lưu trên GitLab,
  auth bằng `gitlab_token`.

---

## Cấu trúc thư mục

```
terraform-vmware/
├── provider.tf              # vcd provider + GitLab http backend
├── variables.tf            # Biến đầu vào (credentials, catalog, sizing...)
├── main.tf                 # Networks + các module VM
├── outputs.tf              # Xuất tên/IP network và VM
├── atlantis.yaml           # Cấu hình Atlantis (autoplan, apply on approved)
├── terraform.tfvars.example
└── modules/
    └── vapp/               # Module tạo vApp/VM (compute, disk, multi-NIC)
```

---

## Network Topology

| Network | Type | Subnet | Gateway | Static IP pool | Mục đích |
|---|---|---|---|---|---|
| `Isolated-Network` | `vcd_network_isolated_v2` | `172.16.10.0/24` | `172.16.10.254` | `.1` – `.100` | Air-gap internal, toàn bộ VM |
| `Routed-Network` | `vcd_network_routed_v2` | `192.168.100.0/24` | `192.168.100.254` | `.1` – `.100` | Kết nối Edge Gateway, SNAT ra internet |

Chỉ Squid (và một số VM dual-homed) có NIC trên `Routed-Network`; các service nội bộ chỉ nằm trên
`Isolated-Network` và ra internet qua Squid proxy.

---

## Quy hoạch VM

IP/spec dưới đây được khai báo trực tiếp trong `main.tf`. Template mặc định: `Ubuntu24`
(catalog `NghiaLT-Catalog`).

| Module | VM name | vCPU | RAM (MB) | OS disk (MB) | Data disk | Isolated IP | Routed IP |
|---|---|---|---|---|---|---|---|
| `squid` | squid | 2 | 2048 | 20480 | — | `172.16.10.1` | `192.168.100.1` |
| `dns` | powerdns | 2 | 2048 | 20480 | — | `172.16.10.2` | `192.168.100.2` |
| `ntpsec` | ntpsec | 2 | 2048 | 20480 | — | `172.16.10.3` | `192.168.100.3` |
| `apt_mirror` | apt-mirror | 2 | 2048 | 20480 | 300 GB | `172.16.10.4` | `192.168.100.4` |
| `vault` | vault | 2 | 2048 | 20480 | — | `172.16.10.5` | — |
| `haproxy` | haproxy | 2 | 4096 | 30720 | — | `172.16.10.6` | `192.168.100.6` |
| `gitlab` | gitlab | 4 | 8192 | 51200 | — | `172.16.10.7` | — |
| `runner` | runner | 4 | 2048 | 20480 | — | `172.16.10.8` | — |
| `harbor` | harbor | 4 | 4096 | 20480 | 50 GB | `172.16.10.9` | — |
| `atlantis` | atlantis | 4 | 2048 | 20480 | — | `172.16.10.10` | — |
| `client` | client (jump) | 2 | 2048 | 20480 | — | `172.16.10.100` | `192.168.100.100` |

> Các node Kubernetes (control plane `.20`, worker `.30`–`.32`) hiện được để dạng comment trong
> `main.tf` / `outputs.tf` — bỏ comment khi cần provision cluster.

---

## Prerequisites

- Terraform >= 1.6
- Tài khoản vCloud Director (Viettel Cloud) với quyền tạo network/vApp trong VDC.
- Catalog + template Ubuntu 24.04 sẵn có trong Org.
- GitLab project + personal access token (cho Terraform http backend).

---

## Cấu hình biến

Copy file mẫu và điền giá trị thật:

```shell
cp terraform.tfvars.example terraform.tfvars
```

| Biến | Mô tả |
|---|---|
| `vcd_user`, `vcd_pass` | Credentials vCloud Director |
| `vcd_org`, `vcd_vdc` | Organization và Virtual Data Center |
| `vcd_edgegateway` | Tên NSX-T Edge Gateway (cho Routed-Network) |
| `vcd_url` | URL API của vCloud Director |
| `catalog_name`, `template_name` | Catalog và OS template (mặc định `Ubuntu24`) |
| `storage_policy` | Storage policy (mặc định `Bronze Storage Policy`) |
| `vm_password` | Mật khẩu OS mặc định của VM |
| `gitlab_token` | Token cho GitLab Terraform http backend |

> `terraform.tfvars` và các file chứa secret đã nằm trong `.gitignore` — không commit.

---

## Sử dụng

```shell
# Khởi tạo provider + backend (state lưu trên GitLab)
terraform init

# Xem plan
terraform plan

# Áp dụng
terraform apply

# Xem output (tên + IP của network và VM)
terraform output
```

---

## GitOps với Atlantis

`atlantis.yaml` cấu hình project `gitops-infrastructure`:

- **Autoplan** khi có thay đổi `*.tf`, `*.tfvars`, hoặc `modules/**/*.tf`.
- **Apply** yêu cầu MR được `approved`.

Workflow: mở MR trên GitLab → Atlantis chạy `terraform plan` và comment kết quả → sau khi approve,
comment `atlantis apply` để áp dụng.

---

## Module `vapp`

Module dùng chung cho mọi VM, hỗ trợ:

- **Compute:** `cpu`, `cpu_core`, `ram`.
- **Storage:** `os_disk_size` + danh sách `data_disks` (mỗi disk có `size_in_mb`, `storage_profile`).
- **Multi-NIC:** danh sách `networks`, thứ tự trong list = thứ tự NIC (index 0 = eth0, ...), mỗi NIC
  có `name`, `ip_allocation_mode` (mặc định `MANUAL`), `ip`, `is_primary`.

Xem chi tiết biến trong `modules/vapp/variables.tf`.
