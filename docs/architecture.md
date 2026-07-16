# Architecture Notes

## Delivery flow

1. **Code & config live in Git.** The repository is the single source of truth
   for both application definitions (Helm) and cluster state (ArgoCD
   `Application` manifests).
2. **CI validates before anything ships.** On every push/PR, GitHub Actions runs
   unit tests, a Trivy filesystem scan, then builds the image and runs a Trivy
   image scan. Only `main` pushes promote the image to GHCR.
3. **ArgoCD reconciles continuously.** The `app-of-apps` pattern points ArgoCD
   at the `argocd/apps/` directory, which in turn manages the `demo-service`
   `Application`. Automated sync with `prune` + `selfHeal` keeps the cluster
   converging to Git.

## Why Kind + local image loading (no registry)

For a zero-cost local demo we avoid a container registry entirely:

- The image is built and tagged `demo-service:latest` locally.
- `kind load docker-image` injects it directly into the cluster's node
  containerd.
- The Helm `imagePullPolicy: IfNotPresent` makes Kubernetes reuse the loaded
  image instead of pulling.

When moving to the cloud, change `image.repository` to your registry
(e.g. `ghcr.io/<you>/gitops-platform/demo-service`) and set `pullPolicy:
IfNotPresent` — nothing else changes.

## Observability design

- The service exposes `/metrics` in Prometheus text format: a request counter,
  an error counter, and a request-latency histogram (with explicit buckets so
  `histogram_quantile` works).
- A `ServiceMonitor` (labeled `release: kube-prometheus-stack`) tells Prometheus
  to scrape `/metrics` every 15s.
- `PrometheusRule` defines SLO-style alerts:
  - **DemoHighErrorRate** — error ratio > 10% over 5m (page-worthy).
  - **DemoHighLatency** — p95 latency > 0.5s over 5m (warning).
- A Grafana dashboard visualizes request rate, error rate, and p95 latency.

## Progressive delivery (optional)

`rollouts/demo-rollout.yaml` deploys an Argo Rollouts `Rollout` instead of a
plain `Deployment`. The canary shifts 20% → 50% with 30s analysis windows
between steps. An `AnalysisTemplate` queries Prometheus for the error ratio; if
it exceeds 10% more than twice, the rollout is automatically aborted and the
stable ReplicaSet is restored — demonstrating automated, metric-based rollback
without manual intervention.

## Failure injection for demos

The service ships two endpoints useful for live demos:

- `GET /fail` returns HTTP 500 — drives the error-rate alert.
- `GET /load?ms=N` adds artificial latency — drives the latency alert and lets
  you watch the Grafana panels react in real time.
