# 在 Linux 虚拟机中部署 GitOps Platform

本文针对「把整套平台跑在一台 Linux 虚拟机（VM）里」的场景，与 Windows 本机路径完全等价，
只是所有命令都在 VM 内执行，访问从你自己的电脑通过 SSH 端口转发完成。

> 零成本、无需 GitHub、无需 ArgoCD。先跑通 `local-apply` fast path，再决定要不要上 GitOps。

---

## 1. 前提条件

- **VM 资源**：建议 ≥ 2 vCPU / 4 GB RAM（Prometheus 栈会多吃内存，4 GB 偏紧，8 GB 更稳）。
- **网络**：VM 需能访问外网（拉镜像、helm repo、`raw.githubusercontent.com`）。
- **系统**：Ubuntu 22.04/24.04 示例，其他发行版改包管理器即可。

---

## 2. 把仓库弄进 VM

任选其一：

**方式 A（推荐，顺带为 GitHub 做准备）**——在 Windows 侧先初始化并推到 GitHub，再在 VM 里 clone：

```bash
# 在 Windows（Git Bash）里
cd /c/Users/Anchnet/WorkBuddy/2026-07-16-16-01-58/gitops-platform
git init && git add -A && git commit -m "init gitops-platform"
git remote add origin https://github.com/<你的账号>/gitops-platform.git
git push -u origin main
```

```bash
# 在 Linux VM 里
sudo apt update && sudo apt install -y git
git clone https://github.com/<你的账号>/gitops-platform.git
cd gitops-platform
```

**方式 B（最快，不碰 GitHub）**——直接从 Windows 把文件夹 scp 进去：

```powershell
# 在 Windows PowerShell
scp -r C:\Users\Anchnet\WorkBuddy\2026-07-16-16-01-58\gitops-platform user@<VM_IP>:~/gitops-platform
```

然后 SSH 进 VM：`ssh user@<VM_IP> && cd ~/gitops-platform`。

---

## 3. 在 VM 里安装依赖

```bash
# 基础工具
sudo apt update
sudo apt install -y docker.io make curl

# 启动 Docker 并授权当前用户（避免每次 sudo）
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker          # 立即生效，或重开 shell

# kubectl
curl -fsSLo /usr/share/keyrings/kubernetes-apt-keyring.gpg \
  https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key
echo 'deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update && sudo apt install -y kubectl

# kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

验证：`docker info`、`kind version`、`kubectl version --client`、`helm version` 都应正常输出。

---

## 4. 一键部署（fast path）

```bash
make kind-up        # 建 Kind 集群（首次拉镜像，稍慢）
make build          # 在 VM 内构建 demo-service 镜像
make kind-load      # 把镜像塞进 Kind（免 registry）
make local-apply    # kubectl + helm 直接部署，不依赖 ArgoCD/GitHub
make observability-up   # Prometheus + Grafana + 告警规则
make status         # 看 pod 状态（demo 命名空间）
make smoke-test     # 跑冒烟测试
```

> 说明：`make ingress-up`（装 ingress-nginx）在云 VM 上其 Service 是 LoadBalancer 类型会一直处于
> `Pending`（VM 没有云负载均衡器）。fast path 我们用 `kubectl port-forward` 访问，因此**可跳过 ingress-up**。
> 想用 ingress，请改用 NodePort 方案（见第 6 节）。

全部就绪后 `kubectl get pods -n demo` 应看到 `demo-*` 处于 `Running`。

---

## 5. 从你的电脑访问（SSH 端口转发）

所有服务都通过 `kubectl port-forward` 绑在 VM 的 localhost，再用 SSH 把端口隧道到你本机：

```bash
# 在 VM 后台启动转发
make port-forward
```

```powershell
# 在 Windows PowerShell 开一条 SSH 隧道（把 VM 的 localhost 映射到你本机）
ssh -N -L 8080:localhost:8080 -L 9090:localhost:9090 -L 3000:localhost:3000 user@<VM_IP>
```

然后在本机浏览器打开：

- 示例服务：**http://localhost:8080** （试 `/`、`/metrics`、`/fail`、`/load`）
- Prometheus：**http://localhost:9090**
- Grafana：**http://localhost:3000** （admin / prom-operator）

> 若想验证告警：对服务打几次 `curl localhost:8080/fail`（在 VM 内），Grafana 面板与 Prometheus 规则会响应。

---

## 6. 可选：用 NodePort 直接对外暴露（更像"真环境"）

若想不经过 SSH 隧道、直接 `http://<VM_IP>:<NodePort>` 访问：

1. 编辑 `apps/demo-service/helm/values.yaml`，把 `service.type` 改为 `NodePort`；
2. 安装 ingress-nginx 为 NodePort：
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
   ```
3. 用 `kubectl get svc -n demo demo-service` 查到的 NodePort 访问。
   （注意 VM 安全组/防火墙需放行对应端口。）

---

## 7. 可选：上真正的 GitOps（ArgoCD）

仓库推到 GitHub 后，改用声明式交付路径（面试更硬核）：

```bash
export REPO_URL=https://github.com/<你的账号>/gitops-platform.git
make argocd-up
make argocd-password   # 打印初始 admin 密码
# UI：kubectl -n argocd port-forward svc/argocd-server 8080:443
```

ArgoCD 会从 Git 拉清单自动 reconcile（自动 sync + prune + selfHeal）。

---

## 8. 清理

```bash
make local-teardown   # 只删 demo-service
make destroy          # 销毁整个 Kind 集群
```
