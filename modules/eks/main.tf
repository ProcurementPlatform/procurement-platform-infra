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
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Gated on var.bastion_enabled (a plain bool, always known at plan time) —
  # NOT on `var.bastion_security_group_id == ""`. That string is computed
  # from module.bastion, which doesn't exist yet on a fresh apply; comparing
  # an unknown value makes the whole conditional (and so the for_each map's
  # key) unknown, which Terraform refuses ("known only after apply") and
  # forced a two-pass apply. The VALUE below can still be unknown at plan
  # time without issue — only a for_each map's KEYS must be statically known.
  cluster_security_group_additional_rules = var.bastion_enabled ? {
    ingress_bastion_https = {
      description              = "Bastion kubectl access to the EKS API"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      type                     = "ingress"
      source_security_group_id = var.bastion_security_group_id
    }
  } : {}

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
