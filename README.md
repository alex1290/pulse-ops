# pulse-ops

用一個簡單的 Node.js API（`pulse-api`）練習完整 DevOps 流程：
**Node.js → Docker → Terraform (AWS) → Kubernetes (EKS) → Jenkins → ArgoCD → Prometheus/Grafana**

```
git push ─► Jenkins ─► test ─► docker build ─► push ECR
                                   │
                                   └─► 更新 pulse-ops-manifests 的 image tag
                                                       │
                                     ArgoCD 偵測 commit ─► 同步到 EKS
                                                       │
                                   Prometheus 抓 /metrics ─► Grafana
```

| Repo | 內容 |
|---|---|
| `pulse-ops`（本 repo） | 應用程式、Dockerfile、Terraform、Jenkinsfile |
| `pulse-ops-manifests` | K8s manifests（Kustomize）、ArgoCD Applications，ArgoCD 只看這個 repo |

## 目錄結構

```
app/                    Node.js API（Express + prom-client）
  src/app.js            路由：/health /ready /metrics / /api/hello /api/slow
  src/index.js          啟動 + graceful shutdown
  test/                 node:test 測試
docker/Dockerfile       multi-stage、non-root、HEALTHCHECK
docker/nginx/nginx.conf Nginx reverse proxy
docker-compose.yml      Nginx + API
terraform/              VPC、EKS、ECR、Jenkins IAM user
scripts/bootstrap-cluster.sh  安裝 ingress-nginx + ArgoCD（local / eks）
Jenkinsfile             CI pipeline
```

## API 端點

| Path | 用途 |
|---|---|
| `GET /health` | Liveness：process 活著就 200 |
| `GET /ready` | Readiness：收到 SIGTERM 後回 503，讓流量先切走 |
| `GET /metrics` | Prometheus 指標 |
| `GET /` | 版本與 hostname（可看出打到哪個 Pod） |
| `GET /api/hello?name=xxx` | 範例 API |
| `GET /api/slow?ms=800` | 模擬慢請求，觀察 Grafana 延遲 |

---

## 階段 1：本機開發

```bash
cd app
npm install
npm test
npm run dev          # http://localhost:3000/health
```

## 階段 2：Docker Compose（Nginx + Node.js）

```bash
docker compose up --build
curl localhost:8080/health
curl localhost:8080/          # 經過 Nginx 轉發
docker compose ps             # 看 healthcheck 狀態
```

## 階段 3：本機 Kubernetes（Docker Desktop，免費）

### 開啟 Kubernetes

1. Docker Desktop → **Settings → Kubernetes** → 勾選 **Enable Kubernetes**
2. Cluster 類型選 **kubeadm**（單節點，直接共用 Docker 的 image，不用另外載入）
3. **Settings → Resources** 建議給 **4 CPU / 8 GB 記憶體** 以上（Prometheus + Grafana + ArgoCD 會吃不少資源）
4. Apply & Restart，等左下角 Kubernetes 顯示綠燈

```bash
kubectl config use-context docker-desktop
kubectl get nodes          # 看到 docker-desktop  Ready
```

> 需要安裝 `helm`：`brew install helm`

### 安裝 ingress-nginx + ArgoCD

```bash
./scripts/bootstrap-cluster.sh local
```

> ingress-nginx 會佔用本機的 **80 / 443 port**。如果 Docker Compose（階段 2）或其他程式正在用，請先停掉。

### 部署 pulse-api

```bash
# Docker Desktop (kubeadm) 和本機 Docker 共用 image，build 完 K8s 就能直接使用
docker build -f docker/Dockerfile -t pulse-api:local ./app

# 方式 A：用 ArgoCD（推薦，manifests repo 需先 push 到 GitHub）
kubectl apply -f ../pulse-ops-manifests/argocd/root-local.yaml

# 方式 B：不用 ArgoCD，直接 apply（需先裝好 monitoring 才有 ServiceMonitor CRD）
kubectl apply -k ../pulse-ops-manifests/overlays/local

kubectl -n pulse-local get pods
curl localhost/health
```

改程式後重新部署：
```bash
docker build -f docker/Dockerfile -t pulse-api:local ./app
kubectl -n pulse-local rollout restart deploy/pulse-api
```

### Grafana

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3001:80
# http://localhost:3001  帳號 admin / 密碼見 monitoring.yaml 的 adminPassword
# Dashboards → pulse-api

# 產生一些流量來看圖
for i in $(seq 1 200); do curl -s localhost/api/hello >/dev/null; curl -s "localhost/api/slow?ms=300" >/dev/null; done
```

### 重置本機叢集

Docker Desktop → Settings → Kubernetes → **Reset Kubernetes Cluster**

## 階段 4：AWS（Terraform）

> ⚠️ EKS control plane、NAT Gateway、Load Balancer 都按小時計費，練習完務必 `terraform destroy`。

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
$(terraform output -raw kubeconfig_command)
kubectl get nodes

../scripts/bootstrap-cluster.sh eks
```

接著：
1. 把 `terraform output ecr_repository_url` 填入 `pulse-ops-manifests/overlays/dev/kustomization.yaml` 和 `Jenkinsfile`
2. `kubectl apply -f ../pulse-ops-manifests/argocd/root-dev.yaml`
3. `kubectl -n ingress-nginx get svc ingress-nginx-controller` 取得 Load Balancer 網址

## 階段 5：Jenkins

本機最快的方式：
```bash
docker run -d --name jenkins -p 8081:8080 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins/jenkins:lts
```
（agent 需要 docker CLI 與 aws CLI，可自行 build 一個包含它們的 Jenkins image。）

1. 建立 access key：`aws iam create-access-key --user-name pulse-ops-jenkins`
2. Jenkins Credentials 新增 `aws-ecr-push`（AWS）與 `github-token`（GitHub PAT）
3. 建立 Multibranch Pipeline 指向本 repo
4. 修改 `Jenkinsfile` 裡的 `AWS_ACCOUNT_ID`、`MANIFESTS_REPO`

## 階段 6：GitOps 驗證

1. 改 `app/src/app.js`（例如 `/api/hello` 的訊息）→ push 到 main
2. Jenkins 建置並推 image → 自動 commit 新 tag 到 manifests repo
3. ArgoCD UI 看到 `pulse-api-dev` 同步 → `kubectl -n pulse-dev rollout status deploy/pulse-api`
4. 想 rollback：在 manifests repo `git revert` 那個 commit 就好

## 清理

```bash
kubectl delete -f ../pulse-ops-manifests/argocd/root-dev.yaml
helm -n ingress-nginx uninstall ingress-nginx   # 先刪 LB，避免 VPC 刪不掉
cd terraform && terraform destroy
```
