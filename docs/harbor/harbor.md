# Harbor

Harbor là private container registry mã nguồn mở của CNCF, tích hợp vulnerability scanning (Trivy), image signing (Cosign), RBAC, và proxy cache cho public registry.

Trong hệ thống, Harbor là registry duy nhất để lưu trữ và phân phối container image. GitLab Runner push image lên Harbor sau mỗi CI build, Kubernetes pull image từ Harbor khi deploy workload. Image phải qua Trivy scan trước khi được phép deploy — không có image nào được pull trực tiếp từ internet vào Kubernetes.

# Prerequisites

- Ubuntu 24.04
- RAM tối thiểu 4GB, khuyến nghị 8GB
- Disk tối thiểu 100GB tại `/opt/harbor/data`
- User có quyền `sudo`
- Docker và Docker Compose đã cài đặt
- Squid Proxy đã hoạt động — tải Harbor installer và Trivy DB update
- Vault PKI đã hoạt động — lấy TLS cert cho `harbor.nghia.internal`
- PowerDNS đã hoạt động — cần DNS record `harbor.nghia.internal`
- Port `443` (HTTPS) không bị firewall block từ GitLab Runner và Kubernetes nodes

# Diagram

```mermaid
graph LR
    A["GitLab Runner"] -->|"docker push\nport 443"| B["Harbor\nharbor.nghia.internal"]
    C["Kubernetes Nodes"] -->|"docker pull\nimagePullSecret"| B
    B --> D["Trivy\nVulnerability Scan"]
    B --- E[("Image Storage\n/opt/harbor/data")]
    B -->|"Proxy cache\nqua Squid"| F["Public Registries\nDocker Hub / GCR / Quay"]
```

---

# Cài đặt

## Cấu hình proxy cho server

Thêm vào file `/etc/environment`:

```sh
http_proxy="http://<USERNAME>:<PASSWORD>@<SQUID_IP>:3128"
https_proxy="http://<USERNAME>:<PASSWORD>@<SQUID_IP>:3128"
no_proxy="localhost,127.0.0.1,172.16.10.0/24,192.168.100.0/24,.nghia.internal"
```

```shell
source /etc/environment
```

## Cài đặt Docker và Docker Compose

```shell
sudo apt update -y && sudo apt upgrade -y

# Cài Docker CE từ aptly mirror
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo systemctl enable docker
sudo systemctl start docker

# Thêm user hiện tại vào docker group
sudo usermod -aG docker $USER

docker version
docker compose version
```

Cấu hình Docker daemon dùng proxy để pull image từ ngoài (qua Squid):

```shell
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://<USERNAME>:<PASSWORD>@<SQUID_IP>:3128"
Environment="HTTPS_PROXY=http://<USERNAME>:<PASSWORD>@<SQUID_IP>:3128"
Environment="NO_PROXY=localhost,127.0.0.1,172.16.10.0/24,192.168.100.0/24,harbor.nghia.internal"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
```

## Lấy TLS certificate từ Vault PKI

Thực hiện trên Vault server:

```shell
export VAULT_ADDR="https://vault.nghia.internal:8200"
vault login <ROOT_TOKEN>

vault write -format=json pki_int/issue/nghia-internal \
  common_name="harbor.nghia.internal" \
  alt_names="harbor.nghia.internal" \
  ip_sans="<HARBOR_IP>" \
  ttl=8760h > /tmp/harbor-cert.json

jq -r '.data.certificate' /tmp/harbor-cert.json > /tmp/harbor.nghia.internal.crt
jq -r '.data.private_key' /tmp/harbor-cert.json > /tmp/harbor.nghia.internal.key

scp /tmp/harbor.nghia.internal.crt <USER>@<HARBOR_IP>:/tmp/
scp /tmp/harbor.nghia.internal.key <USER>@<HARBOR_IP>:/tmp/
```

```shell
# Trên Harbor server
sudo mkdir -p /opt/harbor/certs
sudo mv /tmp/harbor.nghia.internal.crt /opt/harbor/certs/
sudo mv /tmp/harhor.nghia.internal.key /opt/harbor/certs/
sudo chmod 600 /opt/harbor/certs/harbor.nghia.internal.key
```

## Tải Harbor offline installer

Dùng offline installer để không phụ thuộc Docker Hub khi cài. Kiểm tra phiên bản mới nhất tại `https://github.com/goharbor/harbor/releases`.

```shell
cd /tmp

# Tải offline installer qua Squid proxy
curl -fLO https://github.com/goharbor/harbor/releases/download/v2.11.0/harbor-offline-installer-v2.11.0.tgz
curl -fLO https://github.com/goharbor/harbor/releases/download/v2.11.0/harbor-offline-installer-v2.11.0.tgz.asc

# Giải nén
sudo tar -xzf harbor-offline-installer-v2.11.0.tgz -C /opt/
```

## Cấu hình Harbor

Copy file cấu hình mẫu:

```shell
cp /opt/harbor/harbor.yml.tmpl /opt/harbor/harbor.yml
```

Sửa file `/opt/harbor/harbor.yml`:

```yaml
hostname: harbor.nghia.internal

https:
  port: 443
  certificate: /opt/harbor/certs/harbor.nghia.internal.crt
  private_key: /opt/harbor/certs/harbor.nghia.internal.key

# Tắt HTTP redirect — chỉ dùng HTTPS
http:
  port: 80

harbor_admin_password: <HARBOR_ADMIN_PASSWORD>

database:
  password: <HARBOR_DB_PASSWORD>
  max_idle_conns: 50
  max_open_conns: 100
  conn_max_lifetime: 5m
  conn_max_idle_time: 0

data_volume: /opt/harbor/data

trivy:
  ignore_unfixed: false
  # Cho phép Trivy update DB qua proxy — cấu hình proxy ở bước tiếp theo
  skip_update: false
  offline_scan: false
  skip_java_db_update: false
  security_check: vuln
  insecure: false
  timeout: 5m0s
  
jobservice:
  max_job_workers: 10
  logger_sweeper_duration: 1
  max_job_duration_hours: 24
  job_loggers:
    - STD_OUTPUT
    - FILE

notification:
  webhook_job_max_retry: 3
  webhook_job_http_client_timeout: 3

log:
  level: info
  local:
    rotate_count: 50
    rotate_size: 200M
    location: /var/log/harbor
    
_version: 2.14.0

proxy:
  http_proxy: "http://squid-client:Okela123@172.16.10.1:3128"
  https_proxy: "http://squid-client:Okela123@172.16.10.1:3128"
  no_proxy: "localhost,127.0.0.1,harbor.nghia.internal,core,registry,jobservice"
  components:
    - core
    - jobservice
    - trivy
      
metric:
  enabled: false
  port: 9090
  path: /metrics

upload_purging:
  enabled: true
```

Để Trivy có thể update vulnerability database qua Squid proxy, thêm biến môi trường vào `docker-compose.yml` sau khi chạy `prepare`:

```shell
# Chạy prepare để generate docker-compose.yml
sudo /opt/harbor/prepare

# Thêm proxy vào trivy-adapter service trong docker-compose.yml
# Tìm section trivy-adapter và thêm environment variables
```

Sửa `/opt/harbor/docker-compose.yml`, tìm service `trivy-adapter` và thêm:

```yaml
  trivy-adapter:
    environment:
      HTTP_PROXY: "http://<USERNAME>:<PASSWORD>@<SQUID_IP>:3128"
      HTTPS_PROXY: "http://<USERNAME>:<PASSWORD>@<SQUID_IP>:3128"
      NO_PROXY: "localhost,127.0.0.1,172.16.10.0/24,core,registry,jobservice"
```

## Cài đặt Harbor

```shell
sudo /opt/harbor/install.sh --with-trivy

# Kiểm tra tất cả container đang chạy
sudo docker compose -f /opt/harbor/docker-compose.yml ps
```

## Thêm DNS record vào PowerDNS

```shell
sudo pdnsutil add-record nghia.internal harbor A <HARBOR_IP>
sudo pdnsutil rectify-zone nghia.internal

dig @<POWERDNS_IP> harbor.nghia.internal A
```

## Cấu hình Docker daemon trust Harbor Root CA

Thực hiện trên tất cả node cần pull/push image: GitLab Runner, Kubernetes nodes.

```shell
# Tạo thư mục cho Harbor cert
sudo mkdir -p /etc/docker/certs.d/harbor.nghia.internal

# Copy Root CA cert từ Vault (đã lấy trong bước cài Vault)
sudo cp /usr/local/share/ca-certificates/nghia-internal-root-ca.crt \
  /etc/docker/certs.d/harbor.nghia.internal/ca.crt

sudo systemctl restart docker

# Kiểm tra login
docker login harbor.nghia.internal
```

## Kiểm tra Harbor UI

Truy cập `https://harbor.nghia.internal`, đăng nhập với user `admin` và password đã cấu hình trong `harbor.yml`. Đổi password ngay sau lần đầu đăng nhập.

---

## Cấu hình Projects

Harbor tổ chức image theo project. Tạo các project cơ bản:

| Project | Loại | Mục đích |
|---|---|---|
| `library` | Public | Base image (Ubuntu, Alpine, v.v.) — push thủ công hoặc qua proxy cache |
| `internal` | Private | Application image do GitLab Runner build |
| `infra` | Private | Infrastructure tool image (Prometheus, Grafana, ArgoCD...) |

Tạo project qua CLI:

```shell
# Tạo project library (public — base images)
curl -u "admin:<HARBOR_ADMIN_PASSWORD>" \
  -X POST "https://harbor.nghia.internal/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{
    "project_name": "library",
    "public": true,
    "metadata": {"auto_scan": "true"}
  }'

# Tạo project internal (private)
curl -u "admin:<HARBOR_ADMIN_PASSWORD>" \
  -X POST "https://harbor.nghia.internal/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{
    "project_name": "internal",
    "public": false,
    "metadata": {"auto_scan": "true"}
  }'

# Tạo project infra
curl -u "admin:<HARBOR_ADMIN_PASSWORD>" \
  -X POST "https://harbor.nghia.internal/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{
    "project_name": "infra",
    "public": false,
    "metadata": {"auto_scan": "true"}
  }'

# Tạo project quay-proxy (proxy cache cho quay.io — dùng bởi containerd mirror config trong Kubernetes)
curl -u "admin:<HARBOR_ADMIN_PASSWORD>" \
  -X POST "https://harbor.nghia.internal/api/v2.0/registries" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "quay-io",
    "type": "quay",
    "url": "https://quay.io"
  }'

QUAY_REGISTRY_ID=$(curl -s -u "admin:<HARBOR_ADMIN_PASSWORD>" \
  "https://harbor.nghia.internal/api/v2.0/registries?name=quay-io" | \
  jq -r '.[0].id')

curl -u "admin:<HARBOR_ADMIN_PASSWORD>" \
  -X POST "https://harbor.nghia.internal/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d "{
    \"project_name\": \"quay-proxy\",
    \"public\": true,
    \"registry_id\": ${QUAY_REGISTRY_ID},
    \"metadata\": {\"proxy_speed_kb\": \"-1\"}
  }"
```

`auto_scan: true` — Harbor tự động chạy Trivy scan mỗi khi có image mới được push.

## Cấu hình Robot Account

Robot account là service account dành cho automation — GitLab Runner push image, Kubernetes pull image.

Tạo robot account cho **GitLab Runner** (push vào project `internal`):

```shell
curl -u "admin:<HARBOR_ADMIN_PASSWORD>" \
  -X POST "https://harbor.nghia.internal/api/v2.0/robots" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "gitlab-runner",
    "duration": -1,
    "permissions": [
      {
        "kind": "project",
        "namespace": "internal",
        "access": [
          {"resource": "repository", "action": "push"},
          {"resource": "repository", "action": "pull"},
          {"resource": "artifact", "action": "read"}
        ]
      }
    ]
  }'
```

Tạo robot account cho **Kubernetes** (pull từ tất cả project):

```shell
curl -u "admin:<HARBOR_ADMIN_PASSWORD>" \
  -X POST "https://harbor.nghia.internal/api/v2.0/robots" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "kubernetes",
    "duration": -1,
    "permissions": [
      {
        "kind": "project",
        "namespace": "internal",
        "access": [{"resource": "repository", "action": "pull"}]
      },
      {
        "kind": "project",
        "namespace": "infra",
        "access": [{"resource": "repository", "action": "pull"}]
      }
    ]
  }'
```

Lưu token trả về vào Vault:

```shell
vault kv put secret/harbor/robot-accounts \
  gitlab_runner_name="robot\$gitlab-runner" \
  gitlab_runner_token="<ROBOT_TOKEN>" \
  kubernetes_name="robot\$kubernetes" \
  kubernetes_token="<ROBOT_TOKEN>"
```

## Cấu hình Proxy Cache (tùy chọn)

Proxy Cache cho phép Harbor cache image từ public registry. Kubernetes pull image từ Harbor thay vì trực tiếp từ Docker Hub — Harbor tự kéo về qua Squid khi cần.

Tạo endpoint cho Docker Hub:

```shell
curl -u "admin:<HARBOR_ADMIN_PASSWORD>" \
  -X POST "https://harbor.nghia.internal/api/v2.0/registries" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "docker-hub",
    "type": "docker-hub",
    "url": "https://hub.docker.com"
  }'
```

Tạo project proxy cache trỏ về Docker Hub:

```shell
curl -u "admin:<HARBOR_ADMIN_PASSWORD>" \
  -X POST "https://harbor.nghia.internal/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{
    "project_name": "dockerhub-proxy",
    "public": true,
    "registry_id": 1,
    "metadata": {"proxy_speed_kb": "-1"}
  }'
```

Kubernetes pull image từ Docker Hub thông qua Harbor:

```
# Thay vì: nginx:alpine
# Dùng:    harbor.nghia.internal/dockerhub-proxy/library/nginx:alpine
```

## Cấu hình Harbor khởi động cùng hệ thống

Harbor chạy qua Docker Compose, cần thêm systemd service để tự start sau reboot:

```shell
sudo tee /etc/systemd/system/harbor.service <<EOF
[Unit]
Description=Harbor Container Registry
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/harbor
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable harbor
```

## Scan image thủ công

```shell
# Scan một image cụ thể qua API
curl -u "admin:<HARBOR_ADMIN_PASSWORD>" \
  -X POST "https://harbor.nghia.internal/api/v2.0/projects/internal/repositories/<REPO>/artifacts/<TAG>/scan"

# Xem kết quả scan qua Harbor UI:
# Projects → internal → <repository> → <tag> → Vulnerabilities
```
