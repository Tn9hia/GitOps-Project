# Một số thao tác vận hành cụm kubernetest
## etcd Backup / Restore

etcd là database lưu toàn bộ trạng thái của cluster. Backup etcd trước mọi thao tác ảnh hưởng lớn (upgrade, xóa namespace, thay đổi RBAC hàng loạt).

### Backup etcd

Thực hiện trên một trong các control-plane node.

Lấy thông tin endpoint và certificate path từ manifest của etcd:

```shell
sudo grep -E 'listen-client-urls|cert-file|key-file|trusted-ca-file' \
  /etc/kubernetes/manifests/etcd.yaml
```

Chạy backup:

```shell
sudo ETCDCTL_API=3 etcdctl snapshot save /var/backups/etcd/snapshot-$(date +%Y%m%d-%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

Kiểm tra snapshot hợp lệ:

```shell
sudo ETCDCTL_API=3 etcdctl snapshot status /var/backups/etcd/<snapshot-file>.db \
  --write-out=table
```

### Restore etcd

Restore được thực hiện khi cluster bị mất dữ liệu hoặc không thể khởi động. Thực hiện lần lượt trên từng control-plane node.

Dừng static pod etcd bằng cách di chuyển manifest ra khỏi thư mục watched:

```shell
sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/etcd.yaml
```

Đợi kubelet dừng container etcd, kiểm tra:

```shell
sudo crictl ps | grep etcd
```

Xóa data directory cũ:

```shell
sudo rm -rf /var/lib/etcd
```

Restore từ snapshot:

```shell
sudo ETCDCTL_API=3 etcdctl snapshot restore /var/backups/etcd/<snapshot-file>.db \
  --data-dir=/var/lib/etcd \
  --name=k8s-cp1 \
  --initial-cluster=k8s-cp1=https://<CP1_IP>:2380,k8s-cp2=https://<CP2_IP>:2380,k8s-cp3=https://<CP3_IP>:2380 \
  --initial-cluster-token=etcd-cluster-1 \
  --initial-advertise-peer-urls=https://<CP1_IP>:2380
```

Lặp lại lệnh trên tương ứng trên `k8s-cp2` và `k8s-cp3` với `--name` và `--initial-advertise-peer-urls` phù hợp.

Khởi động lại etcd bằng cách đưa manifest trở lại:

```shell
sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/etcd.yaml
```

Kiểm tra etcd cluster health:

```shell
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

---

## Cluster Upgrade (kubeadm)

Upgrade cluster theo thứ tự: control-plane node đầu tiên -> các control-plane còn lại -> worker node. 

**Note:**
- Không được bỏ qua minor version (ví dụ không nhảy thẳng từ 1.29 lên 1.31).

### Upgrade control-plane đầu tiên (k8s-cp1)

Backup etcd trước khi upgrade.

Kiểm tra version available:

```shell
apt-cache madison kubeadm
```

Upgrade `kubeadm`:

```shell
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.xx.y-1.1
sudo apt-mark hold kubeadm
```

Kiểm tra upgrade plan:

```shell
sudo kubeadm upgrade plan
```

Áp dụng upgrade:

```shell
sudo kubeadm upgrade apply v1.xx.y
```

Drain node để migrate workload:

```shell
kubectl drain k8s-cp1 --ignore-daemonsets --delete-emptydir-data
```

Upgrade `kubelet` và `kubectl`:

```shell
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.xx.y-1.1 kubectl=1.xx.y-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

Uncordon node:

```shell
kubectl uncordon k8s-cp1
```

### Upgrade các control-plane còn lại (k8s-cp2, k8s-cp3)

Lặp lại các bước trên với lệnh upgrade khác (không dùng `upgrade apply`):

```shell
sudo kubeadm upgrade node
```

Sau đó drain, upgrade kubelet/kubectl, uncordon tương tự như `k8s-cp1`.

### Upgrade worker node

Thực hiện từng worker một để đảm bảo không downtime.

Drain worker từ control-plane:

```shell
kubectl drain k8s-worker1 --ignore-daemonsets --delete-emptydir-data
```

SSH vào worker node, upgrade kubeadm:

```shell
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.xx.y-1.1
sudo apt-mark hold kubeadm
sudo kubeadm upgrade node
```

Upgrade kubelet:

```shell
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.xx.y-1.1 kubectl=1.xx.y-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

Uncordon từ control-plane:

```shell
kubectl uncordon k8s-worker1
```

Kiểm tra toàn bộ node đã lên version mới:

```shell
kubectl get nodes -o wide
```

---

### Node Management

Quản lý node bao gồm: tạm ngưng lịch pod, drain workload, xóa node khỏi cluster, và taint để phân bổ workload đặc biệt.

### Cordon — ngừng schedule pod mới lên node

Dùng khi cần bảo trì node mà không muốn dừng các pod đang chạy:

```shell
kubectl cordon <node-name>
```

Node sẽ ở trạng thái `SchedulingDisabled`. Các pod hiện tại tiếp tục chạy.

### Drain — di chuyển toàn bộ pod ra khỏi node

Dùng trước khi reboot hoặc xóa node:

```shell
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

`--ignore-daemonsets`: bỏ qua DaemonSet pod (chúng sẽ được tái tạo khi node quay lại).
`--delete-emptydir-data`: chấp nhận xóa pod dùng emptyDir volume.

### Uncordon — cho phép schedule trở lại

Sau khi bảo trì xong:

```shell
kubectl uncordon <node-name>
```

### Xóa node khỏi cluster

Drain trước, sau đó xóa:

```shell
kubectl delete node <node-name>
```

Trên node bị xóa, reset kubeadm để cleanup:

```shell
sudo kubeadm reset
sudo apt-get purge -y kubeadm kubelet kubectl
sudo rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd /root/.kube
```

### Taint — hạn chế hoặc dành riêng node cho workload cụ thể

Thêm taint để chỉ pod có toleration tương ứng mới được schedule lên node:

```shell
kubectl taint nodes <node-name> key=value:NoSchedule
```

Xóa taint:

```shell
kubectl taint nodes <node-name> key=value:NoSchedule-
```

---

## RBAC

RBAC kiểm soát quyền truy cập vào Kubernetes API. Mô hình gồm: `Role`/`ClusterRole` định nghĩa quyền, `RoleBinding`/`ClusterRoleBinding` gán quyền cho user hoặc ServiceAccount.

### Xem RBAC hiện tại

```shell
kubectl get clusterroles | grep -v system:
kubectl get clusterrolebindings | grep -v system:
kubectl get roles -A
kubectl get rolebindings -A
```

### Tạo Role giới hạn trong một namespace

Ví dụ: cho phép đọc pod và log trong namespace `production`:

```yaml
# role-pod-reader.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: production
  name: pod-reader
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
```

```shell
kubectl apply -f role-pod-reader.yaml
```

### Tạo RoleBinding — gán Role cho user

```yaml
# rolebinding-pod-reader.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: production
subjects:
  - kind: User
    name: dev-user
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

```shell
kubectl apply -f rolebinding-pod-reader.yaml
```

### Tạo ClusterRole — quyền trên toàn cluster

Ví dụ: cho phép xem toàn bộ resource ở mọi namespace (read-only):

```yaml
# clusterrole-viewer.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-viewer
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
```

```shell
kubectl apply -f clusterrole-viewer.yaml
```

### Gán ClusterRole cho ServiceAccount

```yaml
# clusterrolebinding-viewer.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-viewer-binding
subjects:
  - kind: ServiceAccount
    name: monitoring-sa
    namespace: monitoring
roleRef:
  kind: ClusterRole
  name: cluster-viewer
  apiGroup: rbac.authorization.k8s.io
```

```shell
kubectl apply -f clusterrolebinding-viewer.yaml
```

### Kiểm tra quyền của user/ServiceAccount

```shell
kubectl auth can-i list pods --namespace=production --as=dev-user
kubectl auth can-i delete deployments --namespace=production --as=dev-user
kubectl auth can-i '*' '*' --as=system:serviceaccount:monitoring:monitoring-sa
```

---

## Kubeconfig / Context

Kubeconfig quản lý thông tin kết nối đến các cluster. Mỗi entry bao gồm cluster (API server endpoint + CA), user (credentials), và context (kết hợp cluster + user + namespace mặc định).

### Xem cấu hình hiện tại

```shell
kubectl config view
kubectl config current-context
kubectl config get-contexts
```

### Thêm cluster mới vào kubeconfig

```shell
kubectl config set-cluster <cluster-name> \
  --server=https://<API_SERVER_IP>:6443 \
  --certificate-authority=/path/to/ca.crt \
  --embed-certs=true
```

### Thêm user (credentials)

Dùng certificate:

```shell
kubectl config set-credentials <user-name> \
  --client-certificate=/path/to/user.crt \
  --client-key=/path/to/user.key \
  --embed-certs=true
```

### Tạo context

```shell
kubectl config set-context <context-name> \
  --cluster=<cluster-name> \
  --user=<user-name> \
  --namespace=production
```

### Chuyển đổi context

```shell
kubectl config use-context <context-name>
```

### Tạo kubeconfig cho user mới

Tạo private key và CSR:

```shell
openssl genrsa -out dev-user.key 4096
openssl req -new -key dev-user.key -out dev-user.csr -subj "/CN=dev-user/O=dev-team"
```

Submit CSR lên Kubernetes để ký bằng cluster CA:

```yaml
# csr.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: dev-user
spec:
  request: <base64 của dev-user.csr>
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
```

```shell
cat dev-user.csr | base64 | tr -d '\n'
kubectl apply -f csr.yaml
kubectl certificate approve dev-user
kubectl get csr dev-user -o jsonpath='{.status.certificate}' | base64 -d > dev-user.crt
```

Tạo kubeconfig từ certificate vừa ký:

```shell
kubectl config set-cluster production-cluster \
  --server=https://<LB_IP>:6443 \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --kubeconfig=dev-user.kubeconfig

kubectl config set-credentials dev-user \
  --client-certificate=dev-user.crt \
  --client-key=dev-user.key \
  --embed-certs=true \
  --kubeconfig=dev-user.kubeconfig

kubectl config set-context dev-user@production \
  --cluster=production-cluster \
  --user=dev-user \
  --namespace=production \
  --kubeconfig=dev-user.kubeconfig

kubectl config use-context dev-user@production \
  --kubeconfig=dev-user.kubeconfig
```

Gửi file `dev-user.kubeconfig` cho user.

### Merge nhiều kubeconfig thành một

```shell
KUBECONFIG=~/.kube/config:/path/to/other.kubeconfig \
  kubectl config view --flatten > ~/.kube/config-merged
```

---

## Certificate / TLS

Kubernetes cluster sử dụng PKI nội bộ. Tất cả certificate nằm trong `/etc/kubernetes/pki/` trên control-plane node. Certificate mặc định có thời hạn 1 năm (trừ CA là 10 năm).

### Kiểm tra ngày hết hạn certificate

```shell
sudo kubeadm certs check-expiration
```

### Renew toàn bộ certificate (trước khi hết hạn)

Thực hiện trên từng control-plane node:

```shell
sudo kubeadm certs renew all
```

Sau khi renew, restart các static pod để load certificate mới:

```shell
sudo crictl ps | grep -E 'kube-apiserver|kube-controller|kube-scheduler|etcd'

sudo crictl stop <container-id-apiserver>
sudo crictl stop <container-id-controller>
sudo crictl stop <container-id-scheduler>
```

Kubelet sẽ tự động khởi động lại các static pod. Cập nhật admin kubeconfig sau renew:

```shell
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
```

### Renew certificate cụ thể

```shell
sudo kubeadm certs renew apiserver
sudo kubeadm certs renew apiserver-kubelet-client
sudo kubeadm certs renew front-proxy-client
sudo kubeadm certs renew etcd-server
sudo kubeadm certs renew etcd-peer
```

### Kiểm tra certificate bằng openssl

```shell
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates -subject -issuer
```

Kiểm tra certificate etcd:

```shell
sudo openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -noout -dates
```
