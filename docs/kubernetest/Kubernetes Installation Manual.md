## Yêu cầu

- 1 k8s controlplan node
- 3 k8s worker node
- OS: Ubuntu 24.04
- Các host có hostname khác nhau

## Cài đặt
### Cấu hình proxy để kết nối internet

- Thêm vào file `/etc/environment`

```sh
# http proxy
http_proxy="http://squid-client:Okela123@172.16.10.12:3128"
# https proxy
https_proxy="http://squid-client:Okela123@172.16.10.12:3128"
# no proxy
no_proxy="localhost,127.0.0.1,172.16.0.0/12"
```

### Thực hiện update apt package và repository

```shell
sudo apt update -y && apt upgrade -y
```


Load các kernel module cần thiết

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

Tắt các swap cho các node - cần phải có

```bash
sudo swapoff -a

cat /etc/fstab | grep -i swap

sudo sed -i '/swap.img/s/^/#/' /etc/fstab

sudo rm -f /swap.img

# Verify
sudo free -h
grep swap /etc/fstab
```

Kiểm tra lại:

```shell
free -h # đảm bảo mục swap là 0
```
### Cài đặt container runtime
#### Cài đặt containerd
Source: https://github.com/containerd/containerd/blob/main/docs/getting-started.md

Download containerd
```bash
wget https://github.com/containerd/containerd/releases/download/v2.3.0/containerd-2.3.0-linux-amd64.tar.gz
```
 
```bash
tar Cxzvf /usr/local containerd-2.3.0-linux-amd64.tar.gz

wget -P /usr/lib/systemd/system/ https://raw.githubusercontent.com/containerd/containerd/main/containerd.service 

systemctl daemon-reload
systemctl enable --now containerd
```

#### Cài đặt runc
Source: https://github.com/opencontainers/runc/releases

```bash
wget https://github.com/opencontainers/runc/releases/download/v1.4.1/runc.amd64
install -m 755 runc.amd64 /usr/local/sbin/runc
```

#### Cài đặt CNI plugins
Source: https://github.com/containernetworking/plugins/releases

```bash
mkdir -p /opt/cni/bin
wget https://github.com/containernetworking/plugins/releases/download/v1.9.1/cni-plugins-linux-amd64-v1.9.1.tgz

tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.9.1.tgz
```

#### Configuring the `systemd` cgroup driver 

```bash
mkdir /etc/containerd/ 
touch /etc/containerd/config.toml
sudo containerd config default > /etc/containerd/config.toml
```

Chỉnh sửa file `/etc/containerd/config.toml` với nội dung như sau

```bash
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  ...
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
```

### Cài đặt kubeadm, kubelet và kubectl

Source: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl

#### Thực hiện update apt package và cài các gói cần thiết

```shell
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

#### Tải public signing key cho Kubernetes package repositories

```shell
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

#### Thêm k8s package repository

```shell
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

#### Thực hiện cài đặt và pin version cho kubelet, kubeadm, kubectl

```shell
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
sudo systemctl start kubelet
```

> [!warning]
> Việc pin version cho kubelet, kubeadm, kubectl là cần thiết nhằm tránh việc vô tình update các package này. Khi thực hiện nâng cấp các package này sẽ có các yêu cầu và bước thực hiện riêng

> [!note]
> Các bước cài đặt container runtime, kubeadm, kubelet, kubectl cần thực hiện trên tất cả các node (Controlplane + Worker)

### Tạo k8s cluster
#### Tạo Control Plane

```bash
sudo kubeadm init \
  --pod-network-cidr=100.64.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --control-plane-endpoint="172.16.10.10:6443" \
  --apiserver-advertise-address="172.16.10.10" 
```

Trong đó:
- `pod-network-cidr`: khai báo cidr dùng để cấp cho pod. Cần planing trước để tránh trùng ip trọng mạng. Các CNI sẽ cần thông tin này
- `service-cidr`: Khai báo cidr dùng cho service k8s.
- `control-plane-endpoint`: Hiện tại có thể bỏ qua, dùng ip node controlplane nhưng trong prod với > 3 node controlplane sẽ cần 1 VIP/Load Balancer endpoint để load balance giữa các node
- `apiserver-advertise-address`: IP của node hiện tại đang khai báo

Sau khi chạy kênh kubeadm init xong thì sẽ nhận được lệnh kubeadm join cùng token để join worker node vào cluster
Ví dụ:

```shell
kubeadm join 172.16.10.10:6443 --token y7biz6.vkuqw3f00gxy3h4r \
	--discovery-token-ca-cert-hash sha256:65e6877c1db351c3236d0f825a30dc4ebb09bac2e320df29e1315228168a61e0
```

> [!warning]
> Nếu trong môi trường air gap thì cần cấu hình thêm proxy cho systemd service

```shell
mkdir -p /etc/systemd/system/containerd.service.d/

cat > /etc/systemd/system/containerd.service.d/http-proxy.conf << 'EOF'
[Service]
Environment="HTTP_PROXY=http://cd-install:vTHZ0Tz1etDHdsagPECe@172.29.25.4:3128"
Environment="HTTPS_PROXY=http://cd-install:vTHZ0Tz1etDHdsagPECe@172.29.25.4:3128"
Environment="NO_PROXY=localhost,127.0.0.1,172.16.0.0/12,10.96.0.0/12,10.244.0.0/16"
EOF

systemctl daemon-reload
systemctl restart containerd
```

Cài đặt kubeconfig để kubectl có thể tương tác với kube-api-server

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
### Setup kubeconfig
```bash
echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> ~/.bashrc
source ~/.bashrc
```

### Cài đặt CNI
#### Calico
```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml

curl https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/custom-resources.yaml -O

kubectl create -f custom-resources.yaml
```

Monitor status
```
watch kubectl get tigerastatus
```

Monitor traffic

```
kubectl port-forward -n calico-system service/whisker 8081:8081
```

#### Cilium 
- Với tool clium-cli
```bash
cilium install \
  --version 1.18.4 \
  --helm-set kubeProxyReplacement=true \
  --helm-set ipam.operator.clusterPoolIPv4PodCIDRList="{100.64.0.0/16}" \
  --helm-set ipam.operator.clusterPoolIPv4MaskSize=24

```


- Với helm

```shell
sudo apt-get install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
```

Cài đặt Cilium

```shell
helm install cilium cilium/cilium --version 1.19.3
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set cni.enabled=true \
  --set operator.enabled=true
```

Kiểm tra kết quả cài đặt

```shell
cilium status --wait
```

Thực hiện các test case cilium để test kết nối

```shell
cilium connectivity test
```
## Các thành phần khác 
### Gateway API
- Cài đặt Gateway API CRDs
```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
```

- Verify CRDs
```bash
kubectl get crd | grep gateway
```
### ETCD Client
```shell
ETCD_VER=v3.5.12

wget https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar xvf etcd-${ETCD_VER}-linux-amd64.tar.gz
sudo cp etcd-${ETCD_VER}-linux-amd64/etcdctl /usr/local/bin/
sudo cp etcd-${ETCD_VER}-linux-amd64/etcdutl /usr/local/bin/
```


### Vertical Pod Autoscalling
```shell
git clone ;https://github.com/kubernetes/autoscaler.git

# Enable VPA
./autoscaler/vertical-pod-autoscaler/hack/vpa-up.sh
```
### Storage
#### Longhorn
- Tạo folder cho longhorn
```bash
sudo mkdir -p /var/lib/longhorn
sudo chmod 700 /var/lib/longhorn

# Tạo partition
sudo parted /dev/sdb mklabel gpt
# Format XFS
sudo apt install xfsprogs
sudo parted /dev/sdb mkpart primary xfs 0% 100%
sudo mkfs.xfs -f /dev/sdb1
# Tạo mount point
sudo mount /dev/sdb1 /var/lib/longhorn
df -h | grep longhorn
```

- Persistent mount point sau khi reboot
```bash
# Get UUID 
sudo blkid /dev/sdb1

# Add vào /etc/fstab
echo "UUID=xxxx-xxxx /var/lib/longhorn-storage xfs defaults,noatime 0 0" | sudo tee -a /etc/fstab

# Test fstab
sudo umount /var/lib/longhorn 
sudo mount -a df -h | grep longhorn
```
- Cài đặt gói cần thiết cho Longhorn (Ubuntu 24.04)
```bash
sudo apt update
sudo apt install -y \
  open-iscsi \
  nfs-common \
  cryptsetup \
  util-linux \
  dmsetup
```
- Bật iSCSI service
```bash
sudo systemctl enable --now iscsid
systemctl status iscsid
```
- Load kernel modules (ngay & sau reboot)
```bash
sudo modprobe iscsi_tcp
sudo modprobe dm_crypt
sudo modprobe nfs

lsmod | egrep 'iscsi|dm_crypt' # Check module is loaded

# Auto load after reboot
echo -e "iscsi_tcp\ndm_crypt" | sudo tee /etc/modules-load.d/longhorn.conf 
echo nfs | sudo tee /etc/modules-load.d/nfs.conf
```
- Verify
```bash
iscsiadm -m node
cryptsetup --version
```
- Tắt multipathd.service
```bash
sudo systemctl stop multipathd
sudo systemctl disable multipathd
sudo systemctl mask multipathd

sudo systemctl stop multipathd.socket
sudo systemctl disable multipathd.socket
sudo systemctl mask multipathd.socket

systemctl status multipathd
```
- Longhorn preflight check
```shell
curl -sSfL -o longhornctl https://github.com/longhorn/cli/releases/download/v1.10.1/longhornctl-linux-amd64

chmod +x longhornctl
./longhornctl check preflight --kubeconfig=<kube-config-file>
```

### Metric Server
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

- Change metrics server deployment
```shell
kubectl -n kube-system edit deploy metric-servers
```
- Change the args tag
```yaml
    spec:
      containers:
      - args:
        - --secure-port=4443
        - --cert-dir=/tmp
        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
        - --kubelet-insecure-tls=true
        - --kubelet-use-node-status-port
        - --metric-resolution=15s
```
