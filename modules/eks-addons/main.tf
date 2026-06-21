# EBS CSI Driver IAM role (IRSA) — AWS Load Balancer Controller's role already
# exists in modules/eks; this is the other cluster add-on that needs its own role.
#
# Only the IAM role lives here. The actual `helm install` for the AWS Load
# Balancer Controller, EBS CSI Driver, and Metrics Server happens in
# scripts/bootstrap-cluster.sh, not as Terraform helm_release resources — see
# the comment there for why (EKS access-entry propagation timing).
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.environment}-ebs-csi-driver"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

# AWS Load Balancer Controller is still required even though app routing moved
# from ALB Ingress to Kgateway — Kgateway's Gateway provisions a Service of
# type LoadBalancer, and this controller is what turns that into the NLB (and
# terminates TLS with the ACM cert). Its IAM role is in modules/eks; the
# `helm install` itself happens in scripts/bootstrap-cluster.sh (see comment
# at the top of this file for why).
