#!/usr/bin/env bash
# Quick smoke test: port-forward the demo-service and hit the key endpoints.
set -euo pipefail

echo "==> Port-forwarding demo-service (background)"
kubectl -n demo port-forward svc/demo-service 8080:8080 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT

sleep 3

echo "==> GET /healthz"
curl -s -o /dev/null -w "HTTP %{http_code}\n" localhost:8080/healthz

echo "==> GET /"
curl -s localhost:8080/; echo

echo "==> GET /metrics (first 6 lines)"
curl -s localhost:8080/metrics | head -n 6

echo "==> Generating some load for metrics"
for i in $(seq 1 20); do curl -s -o /dev/null localhost:8080/load?ms=120; done

echo "Smoke test complete."
