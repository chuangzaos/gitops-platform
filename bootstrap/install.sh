#!/usr/bin/env bash
# Installs ArgoCD into the local Kind cluster and applies the app-of-apps.
# Usage: REPO_URL=https://github.com/<you>/gitops-platform.git bash bootstrap/install.sh
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/YOUR_USERNAME/gitops-platform.git}"

echo "==> Creating argocd namespace"
kubectl create namespace argocd || true

echo "==> Applying ArgoCD install manifest"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for argocd-server to be ready"
kubectl rollout status deployment argocd-server -n argocd --timeout=300s

echo "==> Applying app-of-apps (repo: $REPO_URL)"
sed "s|REPO_URL_PLACEHOLDER|$REPO_URL|g" argocd/app-of-apps.yaml | kubectl apply -n argocd -f -
sed "s|REPO_URL_PLACEHOLDER|$REPO_URL|g" argocd/apps/demo-service.yaml | kubectl apply -n argocd -f -

echo ""
echo "ArgoCD admin initial password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "Port-forward the UI:  kubectl -n argocd port-forward svc/argocd-server 8080:443"
