#!/usr/bin/env bash
# 在 K8s 叢集安裝 ingress-nginx 與 ArgoCD
# 監控 (kube-prometheus-stack) 與 pulse-api 由 ArgoCD 從 pulse-ops-manifests 部署
#
# 用法：
#   ./scripts/bootstrap-cluster.sh local   # Docker Desktop 內建 Kubernetes
#   ./scripts/bootstrap-cluster.sh eks     # AWS EKS
set -euo pipefail

MODE="${1:-local}"   # local | eks

# 防呆：確認目前 kubectl context 跟 MODE 一致，避免裝錯叢集
CTX=$(kubectl config current-context)
echo "==> kubectl context: $CTX"
if [ "$MODE" = "local" ] && [ "$CTX" != "docker-desktop" ]; then
  echo "目前 context 不是 docker-desktop，請先執行：kubectl config use-context docker-desktop" >&2
  exit 1
fi

echo "==> Installing ingress-nginx ($MODE)"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update ingress-nginx
# Docker Desktop 會把 type=LoadBalancer 的 Service 對應到 localhost，
# 所以 local 和 eks 都用同一份 chart；在 EKS 上會自動建立 AWS Load Balancer
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace
kubectl wait -n ingress-nginx --for=condition=ready pod \
  -l app.kubernetes.io/component=controller --timeout=180s

echo "==> Installing ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait -n argocd --for=condition=available deployment/argocd-server --timeout=300s

echo
echo "ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
echo
echo "Open UI:  kubectl -n argocd port-forward svc/argocd-server 8443:443  →  https://localhost:8443"
if [ "$MODE" = "local" ]; then
  echo "Next:     kubectl apply -f ../pulse-ops-manifests/argocd/root-local.yaml"
else
  echo "Next:     kubectl apply -f ../pulse-ops-manifests/argocd/root-dev.yaml"
fi
