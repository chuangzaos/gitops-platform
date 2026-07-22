#!/usr/bin/env bash
# Installs Argo Rollouts (optional progressive-delivery alternative to the
# standard Helm Deployment). Used together with rollouts/demo-rollout.yaml.
set -euo pipefail

echo "==> Installing Argo Rollouts controller"
kubectl create namespace argo-rollouts || true
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

echo "==> Installing kubectl argo rollouts plugin (if krew is available)"
if command -v krew >/dev/null 2>&1; then
  kubectl krew install rollouts || true
fi

echo "==> Applying demo-service Rollout + AnalysisTemplate"
kubectl apply -f rollouts/demo-rollout.yaml

echo ""
echo "Watch the canary:  kubectl -n demo argo rollouts get rollout demo-service"
echo "Promote manually:  kubectl -n demo argo rollouts promote demo-service"
echo "Abort:             kubectl -n demo argo rollouts abort demo-service"
