# Một số cấu hình ngoài
## Tạo quản lý cấu hình ssh

```bash
ssh-keygen -t ed25519
```

## Tạo alias name để thuận tiện ssh

Mở file `~/.ssh/config` và thêm alias name:

```bash
Host client
  HostName 10.10.10.5
  User root
  IdentityFile ~/.ssh/id_ed25519
```

Tạo alias để transfer key tới VM.

```bash
echo "allow() { ssh-copy-id -i ~/.ssh/id_ed25519.pub root@$1; }" >> ~/.bashrc
source ~/.bashrc
```

Sử dụng alias để transfer key:

```bash
allow <IP-VM>
```
