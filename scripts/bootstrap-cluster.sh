#!/usr/bin/env bash
# bootstrap-cluster.sh
# Run once after the EKS cluster is provisioned by Terraform (dev or prod workspace).
# Installs everything that runs *inside* the cluster but isn't a Terraform
# resource, in dependency order:
#   1. AWS Load Balancer Controller, EBS CSI Driver, Metrics Server (helm)
#   2. kube-prometheus-stack (Prometheus + Grafana + Alertmanager) for monitoring
#   3. Gateway API CRDs + Kgateway (Envoy-based app routing)
#   4. ArgoCD + the App-of-Apps from the gitops repo (GitOps takes over from here)
#
# Why these are here and not Terraform helm_release resources: Terraform's
# helm/kubernetes provider computes its auth token once during `terraform
# apply`, right as the cluster is newly created, and can hit an EKS access-entry
# propagation race ("the server has asked for the client to provide
# credentials"). A separate, later CLI step re-authenticates fresh each run and
# isn't subject to that timing window. The IAM roles these charts need still
# come from Terraform (modules/eks, modules/eks-addons) — only the `helm
# install` lives here.
#
# Prerequisites:
#   - AWS CLI configured and authenticated
#   - kubectl and helm (3.8+) installed
#   - Terraform workspace for $ENV already applied
#
# Usage:
#   ./scripts/bootstrap-cluster.sh dev
#   ./scripts/bootstrap-cluster.sh prod

set -euo pipefail

ENV=${1:?Usage: $0 <dev|prod>}
AWS_REGION="us-east-1"
GITOPS_REPO_URL="https://github.com/ProcurementPlatform/procurement-platform-gitops.git"
GITOPS_BRANCH=$([ "$ENV" = "prod" ] && echo "main" || echo "develop")

# Pin these — bump deliberately. GATEWAY_API_VERSION is the upstream Kubernetes
# Gateway API release (provides the Gateway/HTTPRoute/GatewayClass CRDs);
# KGATEWAY_VERSION is the Kgateway control plane + its own CRDs.
GATEWAY_API_VERSION="v1.2.1"
KGATEWAY_VERSION="v2.0.0"

# Grafana admin password. Override by exporting GRAFANA_ADMIN_PASSWORD before
# running; defaults to a dev-only value you should change after first login.
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"

echo "==> Selecting Terraform workspace $ENV..."
terraform workspace select "$ENV"

echo "==> Fetching Terraform outputs for $ENV..."
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
LBC_ROLE_ARN=$(terraform output -raw eks_lbc_role_arn)
EBS_CSI_ROLE_ARN=$(terraform output -raw eks_ebs_csi_role_arn)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Cluster: $CLUSTER_NAME"
echo "Account: $ACCOUNT_ID"

echo "==> Configuring kubectl..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

# AWS Load Balancer Controller, EBS CSI Driver, and Metrics Server install here,
# not as Terraform helm_release resources — Terraform's helm/kubernetes provider
# computes its auth token once during `terraform apply`, right as the cluster is
# newly created, and can hit an EKS access-entry propagation race ("the server
# has asked for the client to provide credentials"). A separate, later CLI step
# re-authenticates fresh and isn't subject to that timing window. Their IAM
# roles still come from Terraform (modules/eks, modules/eks-addons) — only the
# actual `helm install` moves here, same reasoning as Kgateway/ArgoCD below.
echo "==> Installing AWS Load Balancer Controller..."
helm repo add eks https://aws.github.io/eks-charts --force-update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=true \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${LBC_ROLE_ARN}" \
  --wait

echo "==> Installing EBS CSI Driver..."
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver --force-update
helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.create=true \
  --set controller.serviceAccount.name=ebs-csi-controller-sa \
  --set "controller.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${EBS_CSI_ROLE_ARN}" \
  --wait

echo "==> Installing Metrics Server..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --wait

echo "==> Installing kube-prometheus-stack (Prometheus + Grafana + Alertmanager)..."
# One chart installs Prometheus, Grafana, Alertmanager, node-exporter, and
# kube-state-metrics. Grafana ships with the Kubernetes dashboards preloaded.
# Service stays ClusterIP (no extra ELB cost) — reach it via port-forward; see
# the summary printed at the end.
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword="$GRAFANA_ADMIN_PASSWORD" \
  --set grafana.service.type=ClusterIP \
  --wait

echo "==> Installing Kubernetes Gateway API CRDs ($GATEWAY_API_VERSION)..."
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

echo "==> Installing Kgateway ($KGATEWAY_VERSION)..."
# CRDs first, then the control plane. OCI registry — helm 3.8+ required.
helm upgrade --install kgateway-crds \
  oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
  --namespace kgateway-system --create-namespace \
  --version "$KGATEWAY_VERSION" --wait
helm upgrade --install kgateway \
  oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --namespace kgateway-system \
  --version "$KGATEWAY_VERSION" --wait
# The kgateway controller creates the `kgateway` GatewayClass that the gitops
# Gateway references. Confirm it registered before handing off to ArgoCD.
kubectl wait --for=condition=Accepted gatewayclass/kgateway --timeout=120s || \
  echo "WARN: kgateway GatewayClass not Accepted yet — ArgoCD will reconcile once it is."

echo "==> Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=LoadBalancer \
  --set server.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing \
  --set server.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-nlb-target-type"=ip \
  --set server.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=external \
  --wait

echo "==> Cloning gitops repo (branch: $GITOPS_BRANCH)..."
TMP_DIR=$(mktemp -d)
git clone --branch "$GITOPS_BRANCH" --depth 1 "$GITOPS_REPO_URL" "$TMP_DIR/gitops"

echo "==> Applying ArgoCD App-of-Apps for $ENV..."
kubectl apply -f "$TMP_DIR/gitops/applications/environments/$ENV/platform.yaml"
rm -rf "$TMP_DIR"

echo ""
echo "==> Bootstrap complete!"
echo ""
echo "ArgoCD admin password (login once and change it):"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "ArgoCD server URL (may take 2-3 mins for LB to provision):"
kubectl -n argocd get svc argocd-server -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
echo ""
echo ""
echo "Grafana (ClusterIP — reach it locally with a port-forward):"
echo "  kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80"
echo "  then open http://localhost:3000  (user: admin / pass: \$GRAFANA_ADMIN_PASSWORD)"
echo ""
echo "Prometheus (same pattern):"
echo "  kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
echo ""
