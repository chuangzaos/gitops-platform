#!/usr/bin/env bash
# Installs the kube-prometheus-stack (Prometheus + Grafana + Alertmanager),
# applies demo-service alert rules and imports a Grafana dashboard.
set -euo pipefail

echo "==> Adding prometheus-community helm repo"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "==> Installing kube-prometheus-stack into 'monitoring'"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --wait

echo "==> Applying PrometheusRule alert rules"
kubectl apply -f observability/alerts/demo-alerts.yml

echo "==> Importing Grafana dashboard (ConfigMap)"
kubectl create configmap demo-service-dashboard \
  --from-file=demo.json=observability/grafana/demo-dashboard.json \
  --namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Done. Access:"
echo "  prometheus : kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
echo "  grafana    : kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80  (admin / prom-operator)"
echo ""
echo "Optional Loki (log aggregation):"
echo "  helm upgrade --install loki grafana/loki-stack -n logging --create-namespace"
