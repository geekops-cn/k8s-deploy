# Ansible RKE2 离线部署

使用 Ansible 自动化部署 RKE2 Kubernetes 集群，支持离线安装和私有 Harbor 镜像仓库集成。

部署前提：

- 所有节点已安装好操作系统（如 rocky Linux 9.7）
- 所有节点之间可以通过 SSH 无密码登录
- 控制节点已安装好 Ansible（版本 >= 2.10）
- 使用 `sync-harbor-images.sh` 同步镜像到 Harbor 私有仓库

## 项目结构

```
ansible-rke2/
├── ansible.cfg                 # Ansible 配置文件
├── files/
│   ├── harbor/
│   │   └── harbor.crt          # Harbor CA 证书
│   └── rke2/
│       ├── install.sh          # RKE2 安装脚本
│       ├── rke2.linux-amd64.tar.gz  # RKE2 离线安装包
│       └── sha256sum-amd64.txt       # 校验文件
├── inventories/
│   └── geekops/
│       ├── group_vars/
│       │   ├── all.yml         # 全局变量
│       │   └── rke2_servers.yml  # RKE2 Server 变量
│       └── hosts.ini           # 主机清单
├── playbooks/
│   ├── 00-connectivity-ping.yml    # 连通性测试
│   ├── 10-os-baseline-rke2.yml     # 操作系统基线配置
│   ├── 20-harbor-trust-ca.yml      # 配置 Harbor CA 信任
│   ├── 30-rke2-install-servers.yml  # 安装 RKE2 Server
│   ├── 31-rke2-bootstrap-first-master.yml  # 引导第一个 Master
│   ├── 31a-rke2-debug-first-master.yml
│   └── 32-rke2-join-other-masters.yml     # 加入其他 Master
└── templates/
    └── rke2/
        ├── config.yaml.j2       # RKE2 配置模板
        └── registries.yaml.j2   # 镜像仓库配置模板
```

## 部署步骤

### 1. 准备工作

确保 Ansible 控制节点已准备好，并且目标节点可以通过 SSH 访问。

### 2. 配置变量

编辑 `inventories/geekops/group_vars/rke2_servers.yml`，根据实际环境修改以下配置：

- **Harbor 配置**：`harbor_domain`、`harbor_registry`、`harbor_username`、`harbor_password`
- **RKE2 版本**：`rke2_version`
- **集群配置**：`rke2_first_master`、`rke2_server_url`、`rke2_token`
- **TLS SANs**：`rke2_tls_sans`
- **离线文件路径**：`rke2_artifact_path_local`、`rke2_artifact_path_remote`
- **NTP 服务器**：`ntp_servers`

### 3. 配置主机清单

编辑 `inventories/geekops/hosts.ini`，根据实际环境修改主机名和 IP 地址。

### 4. 执行部署

按顺序执行以下 Playbook：

#### 步骤 1: 测试连通性

```bash
ansible-playbook playbooks/00-connectivity-ping.yml
```

#### 步骤 2: 配置操作系统基线

```bash
ansible-playbook playbooks/10-os-baseline-rke2.yml
```

该 Playbook 会完成以下配置：
- 设置主机名和 /etc/hosts
- 配置时间同步（chrony）
- 配置 SELinux
- 配置防火墙（关闭或开放端口）
- 加载内核模块（overlay、br_netfilter）
- 配置 sysctl 参数
- 关闭 Swap

#### 步骤 3: 配置 Harbor CA 信任

```bash
ansible-playbook playbooks/20-harbor-trust-ca.yml
```
> 需要预先将 Harbor CA 证书 `files/harbor/harbor.crt` 上传到控制节点

该 Playbook 会：
- 将 Harbor CA 证书添加到系统信任存储
- 为 containerd 配置 Harbor CA 证书

#### 步骤 4: 安装 RKE2 Server
```bash
ansible-playbook playbooks/30-rke2-install-servers.yml
```

该 Playbook 会：
- 上传离线安装文件到目标节点
- 渲染 RKE2 配置文件
- 安装 RKE2 Server

#### 步骤 5: 引导第一个 Master

```bash
ansible-playbook playbooks/31-rke2-bootstrap-first-master.yml
```

#### 步骤 6: 加入其他 Master 节点

```bash
ansible-playbook playbooks/32-rke2-join-other-masters.yml
```

## 验证集群

部署完成后，在第一个 Master 节点上验证集群状态：

```bash
ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

kubectl get nodes -o wide
kubectl get pods -A

# 查看节点状态
kubectl get nodes

# 查看 Pod 状态
kubectl get pods -A
```

## 注意事项

1. **离线文件**：确保 `files/rke2/` 目录下存在完整的 RKE2 离线安装文件
2. **Harbor 证书**：确保 `files/harbor/harbor.crt` 是正确的 Harbor CA 证书
3. **rke2_token**：生产环境请使用强随机字符串
4. **时间同步**：确保所有节点时间同步，etcd 对时间漂移敏感
5. **主机名**：确保主机名稳定且可解析
