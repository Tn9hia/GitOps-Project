# Terraform — OpenStack

Bộ Terraform provisioning hạ tầng air-gap cho bài **Air-Gap GitOps Lab** trên **OpenStack**. Đây là
một trong hai target IaC của project — target còn lại là `../terraform-vmware/`. Xem tổng quan kiến
trúc ở [`../README.md`](../README.md).

> **Trạng thái:** đang thực hiện.


---

## Khác biệt thiết kế so với VMware

Trên OpenStack, các service **có thể chạy trên Kubernetes** được gom vào cụm k8s (deploy qua ArgoCD)
thay vì tách thành VM riêng, nhằm giảm số VM phải quản lý:

| Service | VMware (VM riêng) | OpenStack |
|---|---|---|
| Vault | VM | Trong k8s |
| Harbor | VM | Trong k8s |
| Atlantis | VM | Trong k8s |
| cert-manager | — | Trong k8s (mới) |
| Falco | — | Trong k8s (mới) |
| Velero | — | Trong k8s (mới) |

Các service còn phải là VM (chạy trước / ngoài k8s): **squid, powerdns, ntpsec, apt-mirror, gitlab,
gitlab-runner, haproxy, jump host**, cùng **3 control plane + 3 worker** của k8s.

> **Lưu ý bootstrap:** Harbor (registry) chạy trong k8s trong khi k8s lại cần image để khởi động —
> giai đoạn đầu vẫn pull image qua Squid từ upstream (hoặc apt-mirror/registry tạm), sau khi Harbor
> sẵn sàng mới chuyển sang dùng Harbor làm registry nội bộ.

---

## Nội dung

Bộ code này (dự kiến) tạo ra:

- **Network** trên OpenStack: internal network (air-gap) + external network cho floating IP.
- **Security group** kiểm soát traffic đông-tây và ra internet qua Squid.
- Các **VM hạ tầng** dựng từ module `modules/instance` (mỗi VM một instance), gắn `fixed_ip_v4`
  tĩnh (không DHCP), floating IP tùy chọn.

Provider khai báo trong `provider.tf`:

- Provider: `terraform-provider-openstack/openstack`.
- Auth: Keystone (`auth_url`, `region`, `tenant_name`, credentials) — điền qua `terraform.tfvars`.

---

## Cấu trúc thư mục

```
terraform-openstack/
├── provider.tf              # openstack provider (Keystone auth)
├── variables.tf            # Biến credentials (ops_*)
├── main.tf                 # Networks + các module instance
├── output.tf
├── terraform.tfvars        # Credentials thật (không commit)
└── modules/
    └── instance/           # Module tạo VM (compute, block device, network, floating IP)
```

---

## Module `instance`

Module dùng chung cho mọi VM, hỗ trợ:

- **Compute:** chọn image qua `vm_image_name`, flavor qua `vm_flavor_name`, `vm_key_pair`,
  `vm_availability_zone`, `vm_security_groups`.
- **Block storage:** `vm_block_devices` — mỗi device khai báo `source_type` (`image`/`volume`/`blank`/
  `snapshot`), `volume_size`, `boot_index` (`0` = boot, `-1` = data), `delete_on_termination`.
- **Network:** `vm_networks` — mỗi entry tạo một NIC với `fixed_ip_v4` tĩnh (no DHCP); entry đầu là
  interface chính.
- **Floating IP:** chỉ tạo khi set `vm_floating_ip_pool` (tên external network); có thể chỉ định
  `vm_floating_ip_fixed_ip` để bind vào IP nội bộ cụ thể.

Xem chi tiết biến (kèm giá trị default) trong `modules/instance/variables.tf`.

---

## Prerequisites

- Terraform >= 1.6
- Tài khoản OpenStack (Keystone) với quyền tạo network / instance / floating IP trong project.
- Keypair đã import sẵn (SSH public key) và security group phù hợp.
- Image Ubuntu 24.04 sẵn có trong project.

---

## Cấu hình biến

Điền credentials và tham số môi trường vào `terraform.tfvars` (không commit):

| Biến | Mô tả |
|---|---|
| `ops_username` | Username Keystone |
| `ops_password` | Password Keystone |
| `ops_auth_url` | Keystone auth URL |
| `ops_region` | Region |
| `ops_tenant_name` | Tenant / project name |

> `terraform.tfvars` chứa secret — đã nằm trong `.gitignore`, không commit.

---

## Sử dụng

```shell
terraform init
terraform plan
terraform apply
terraform output
```
