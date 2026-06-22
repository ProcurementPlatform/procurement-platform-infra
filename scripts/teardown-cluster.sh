#!/usr/bin/env bash
# teardown-cluster.sh
# Run this BEFORE `terraform destroy` whenever you tear down a cluster.
#
# The AWS Load Balancer Controller (running inside the cluster) creates the
# NLBs for the app Gateway, ArgoCD, and Grafana. Those NLBs are NOT in
# Terraform state. If `terraform destroy` removes the EKS cluster first, it
# kills the controller before it can delete its NLBs — the orphaned NLBs keep
# ENIs + public IPs in the VPC's subnets, and Terraform then fails to delete
# the subnets / Internet Gateway with "DependencyViolation".
#
# This script deletes those in-cluster LoadBalancers while the cluster (and the
# controller) is still alive, then waits for the NLBs/ENIs to actually be
# released — so the subsequent `terraform destroy` is clean.
#
# Usage:
#   ./scripts/teardown-cluster.sh prod
#   terraform destroy -var-file=prod.tfvars -var="create_global_resources=true" -target=module.vpc -target=module.eks ...

set -uo pipefail

ENV=${1:?Usage: $0 <dev|prod>}
AWS_REGION="us-east-1"

echo "==> Selecting Terraform workspace $ENV..."
terraform workspace select "$ENV"

CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || true)
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || true)

if [ -z "$CLUSTER_NAME" ]; then
  echo "No eks_cluster_name output — cluster may already be gone. Nothing to tear down."
  exit 0
fi

echo "==> Configuring kubectl for $CLUSTER_NAME..."
if ! aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" 2>/dev/null; then
  echo "Cluster $CLUSTER_NAME not reachable — likely already destroyed. Nothing to tear down."
  exit 0
fi

# Delete the Kgateway Gateway first so Kgateway tears down its Envoy
# LoadBalancer Service and does NOT recreate it (deleting just the Service
# would let Kgateway re-provision it).
echo "==> Deleting Gateway in procurement-$ENV (releases the app NLB)..."
kubectl delete gateway --all -n "procurement-$ENV" --ignore-not-found --timeout=90s || true

# Delete every remaining Service of type LoadBalancer across all namespaces
# (ArgoCD, Grafana, and anything else). Each deletion makes the LB Controller
# delete the backing NLB and release its ENIs.
echo "==> Deleting all remaining LoadBalancer Services..."
kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
  | while read -r ns name; do
      [ -n "${name:-}" ] || continue
      echo "  deleting svc $ns/$name"
      kubectl delete svc "$name" -n "$ns" --ignore-not-found --timeout=90s || true
    done

# Wait for the controller to actually delete the NLBs (and their ENIs) before
# Terraform tears down the VPC. Poll until no ELB ENIs remain in the VPC.
if [ -n "$VPC_ID" ]; then
  echo "==> Waiting for ELB ENIs in $VPC_ID to release (up to ~5 min)..."
  for _ in $(seq 1 30); do
    COUNT=$(aws ec2 describe-network-interfaces --region "$AWS_REGION" \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=description,Values=ELB net/*" \
      --query "length(NetworkInterfaces)" --output text 2>/dev/null || echo "?")
    echo "  $COUNT ELB ENIs remaining"
    [ "$COUNT" = "0" ] && break
    sleep 10
  done
fi

echo ""
echo "==> Teardown prep complete — safe to run 'terraform destroy' now."
