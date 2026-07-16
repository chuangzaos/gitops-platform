SHELL := /usr/bin/env bash
REPO_URL ?= https://github.com/YOUR_USERNAME/gitops-platform.git
IMAGE := demo-service
TAG := latest
CLUSTER := gitops-platform

.PHONY: help kind-up kind-down ingress-up build kind-load argocd-up argocd-password \
        observability-up rollouts-up deploy local-apply local-teardown \
        status port-forward smoke-test destroy

help: ## Show available targets
	@echo "GitOps Platform - local-first, zero cost"
	@echo ""
	@echo "Fast path (no GitHub, no ArgoCD):"
	@echo "   kind-up  ingress-up  build  kind-load  local-apply  observability-up"
	@echo "GitOps path (push repo to GitHub first):"
	@echo "   kind-up  ingress-up  build  kind-load  argocd-up  observability-up"
	@echo "Rollouts: rollouts-up   (optional canary + auto-rollback)"
	@echo "Usage:    deploy  status  port-forward  smoke-test"
	@echo "Teardown: local-teardown  |  destroy"

kind-up: ## Create local Kind cluster
	kind create cluster --name $(CLUSTER) --config bootstrap/kind-cluster.yaml

kind-down: ## Delete local Kind cluster
	kind delete cluster --name $(CLUSTER)

ingress-up: ## Install ingress-nginx for Kind
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
	kubectl wait --namespace ingress-nginx \
	  --for=condition=ready pod \
	  --selector=app.kubernetes.io/component=controller \
	  --timeout=180s

build: ## Build the demo-service image
	docker build -t $(IMAGE):$(TAG) apps/demo-service

kind-load: ## Load the image into the Kind cluster
	kind load docker-image $(IMAGE):$(TAG) --name $(CLUSTER)

argocd-up: ## Install ArgoCD and apply app-of-apps
	REPO_URL=$(REPO_URL) bash bootstrap/install.sh

argocd-password: ## Print ArgoCD admin password
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

observability-up: ## Install Prometheus + Grafana + alerts + dashboard
	bash observability/install.sh

rollouts-up: ## (Optional) Install Argo Rollouts + canary Rollout
	bash rollouts/install.sh

deploy: ## (Re)apply the demo-service Application
	kubectl apply -n argocd -f <(sed "s|REPO_URL_PLACEHOLDER|$(REPO_URL)|g" argocd/apps/demo-service.yaml)

local-apply: ## Deploy directly via kubectl+helm (no ArgoCD, no GitHub needed)
	kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -
	helm template demo apps/demo-service/helm --namespace demo | kubectl apply -f -

local-teardown: ## Remove the demo-service deployed by local-apply
	helm template demo apps/demo-service/helm --namespace demo | kubectl delete --ignore-not-found -f -

status: ## Show pods and ArgoCD Applications
	kubectl get pods -n demo; kubectl get app -n argocd

port-forward: ## Port-forward demo / prometheus / grafana
	@echo "demo -> http://localhost:8080   prometheus -> :9090   grafana -> :3000 (admin/prom-operator)"
	kubectl -n demo port-forward svc/demo-service 8080:8080 &
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80 &

smoke-test: ## Run a quick HTTP smoke test against the service
	bash scripts/smoke-test.sh

destroy: kind-down ## Tear everything down
