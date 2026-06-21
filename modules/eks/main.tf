# Canonical's official EKS-optimized Ubuntu AMI, looked up via their published
# SSM parameter. NOT independently verified against AWS for this account/region
# — run the lookup yourself before relying on it:
#   aws ssm get-parameter --name /aws/service/canonical/ubuntu/eks/22.04/1.30/stable/current/amd64/hvm/ebs-gp2/ami-id --region us-east-1
# If that fails or the bootstrap is wrong, nodes never report Ready and the
# node group hangs in "Still creating..." exactly like the AL2 incident did —
# watch this closely, and abort well before 30 minutes if it doesn't settle.
data "aws_ssm_parameter" "ubuntu_eks_ami" {
  count = var.use_ubuntu_ami ? 1 : 0
  name  = var.ubuntu_ami_ssm_path
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.environment}-eks"
  cluster_version = "1.30"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  create_cloudwatch_log_group    = false
  cluster_endpoint_public_access = true
  # NOT enable_cluster_creator_admin_permissions: that grants access to
  # whoever happens to run `terraform apply` (you locally, or CI), and since
  # EKS only allows one access entry per principal, it actively conflicts
  # with admin_principal_arns below whenever the applier is also in that
  # list — confirmed by a real ResourceInUseException. Nothing in this config
  # uses the kubernetes/helm provider anymore (moved to bootstrap-cluster.sh),
  # so CI never needs Kubernetes RBAC access at all. admin_principal_arns is
  # the sole, permanent, explicit grant — never displaced by who applies.
  access_entries = {
    for idx, arn in var.admin_principal_arns : "admin-${idx}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
  # Public endpoint stays on (with the default 0.0.0.0/0 cidrs) deliberately:
  # GitHub Actions runner IPs are ephemeral/unenumerable, and bootstrap-cluster.sh
  # runs from a laptop on varying networks. Both findings are suppressed in
  # .tfsec/config.yml with this same reasoning. Real access control is IAM/EKS
  # access entries + Kubernetes RBAC, not network-layer restriction.
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Manage the VPC CNI as an addon so we can turn on prefix delegation. This
  # raises the per-node pod cap dramatically (t3.medium: 17 -> ~110 pods), which
  # is what lets BOTH the procurement-dev and procurement-prod namespaces — plus
  # ArgoCD, Kgateway/Envoy, and the other add-ons — fit on just 2x t3.medium.
  # before_compute = true applies the CNI config before nodes join, so even the
  # initial node group gets prefix delegation (no node recycle needed).
  cluster_addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }

  eks_managed_node_groups = {
    app_nodes = merge(
      {
        min_size     = var.node_min_size
        max_size     = var.node_max_size
        desired_size = var.node_desired_size

        instance_types = var.node_instance_types
      },
      var.use_ubuntu_ami ? {
        ami_type                   = "CUSTOM"
        ami_id                     = data.aws_ssm_parameter.ubuntu_eks_ami[0].value
        enable_bootstrap_user_data = true
      } : {}
    )
  }

  enable_irsa = true

  tags = var.tags
}

# AWS Load Balancer Controller IAM Role
module "load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.environment}-aws-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
