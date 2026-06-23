locals {
  environment = terraform.workspace
  services    = ["frontend", "identity-service", "procurement-service", "finance-service", "document-service", "ai-service"]

  dynamodb_tables = {
    "Identity_User" = [{ index_name = "emailIndex", attribute_name = "email" }]
    "Procurement_Vendor" = [
      { index_name = "vendorCodeIndex", attribute_name = "vendorCode" },
      { index_name = "vendorEmailIndex", attribute_name = "email" },
    ]
    "Procurement_PurchaseRequest" = [
      { index_name = "prVendorIndex", attribute_name = "vendor" },
      { index_name = "prStatusIndex", attribute_name = "status" },
      { index_name = "prRequestedByIndex", attribute_name = "requestedBy" },
    ]
    "Procurement_PurchaseOrder" = [
      { index_name = "poNumberIndex", attribute_name = "poNumber" },
      { index_name = "poVendorIndex", attribute_name = "vendor" },
      { index_name = "poStatusIndex", attribute_name = "status" },
    ]
    "Procurement_Contract" = [
      { index_name = "contractVendorIndex", attribute_name = "vendor" },
      { index_name = "contractNumberIndex", attribute_name = "contractNumber" },
      { index_name = "contractStatusIndex", attribute_name = "status" },
    ]
    "Finance_Invoice" = [
      { index_name = "invoiceNumberIndex", attribute_name = "invoiceNumber" },
      { index_name = "invoiceTypeIndex", attribute_name = "invoiceType" },
      { index_name = "invoiceStatusIndex", attribute_name = "status" },
      { index_name = "invoiceCreatedByIndex", attribute_name = "createdBy" },
    ]
    "Finance_Payment" = [
      { index_name = "paymentRefIndex", attribute_name = "paymentReference" },
      { index_name = "paymentInvoiceIndex", attribute_name = "invoice" },
      { index_name = "paymentVendorIndex", attribute_name = "vendor" },
      { index_name = "paymentStatusIndex", attribute_name = "status" },
    ]
    "Finance_Customer" = [
      { index_name = "customerCodeIndex", attribute_name = "customerCode" },
      { index_name = "customerEmailIndex", attribute_name = "email" },
      { index_name = "customerStatusIndex", attribute_name = "status" },
    ]
    "Document_Document" = [
      { index_name = "documentCategoryIndex", attribute_name = "category" },
      { index_name = "documentRelatedIdIndex", attribute_name = "relatedId" },
    ]
    "Document_AuditLog" = [
      { index_name = "auditUserIdIndex", attribute_name = "userId" },
      { index_name = "auditEntityIndex", attribute_name = "entity" },
    ]
    "Document_Notification" = [
      { index_name = "notificationUserIdIndex", attribute_name = "userId" },
    ]
    "AI_ContractAnalysis" = [
      { index_name = "contractAnalysisDocumentIdIndex", attribute_name = "documentId" },
      { index_name = "contractAnalysisStatusIndex", attribute_name = "status" },
    ]
    "AI_Embedding" = [
      { index_name = "embeddingDocumentIdIndex", attribute_name = "documentId" },
      { index_name = "embeddingCategoryIndex", attribute_name = "category" },
      { index_name = "embeddingRelatedIdIndex", attribute_name = "relatedId" },
      { index_name = "embeddingOwnerVendorIndex", attribute_name = "ownerVendorId" },
    ]
    "AI_InvoiceAnalysis" = [
      { index_name = "invoiceAnalysisInvoiceIdIndex", attribute_name = "invoiceId" },
      { index_name = "invoiceAnalysisRiskLevelIndex", attribute_name = "riskLevel" },
    ]
    "AI_Feedback" = [
      { index_name = "feedbackFeatureIndex", attribute_name = "feature" },
      { index_name = "feedbackReferenceIdIndex", attribute_name = "referenceId" },
      { index_name = "feedbackUserIdIndex", attribute_name = "userId" },
    ]
  }
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source          = "./modules/vpc"
  environment     = local.environment
  vpc_cidr        = var.vpc_cidr
  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  tags            = var.tags
}

module "kms" {
  source      = "./modules/kms"
  environment = local.environment
  tags        = var.tags
}

module "bastion" {
  source            = "./modules/bastion"
  enabled           = var.enable_bastion
  environment       = local.environment
  vpc_id            = module.vpc.vpc_id
  private_subnet_id = module.vpc.private_subnets[0]
  # Computed independently of module.eks.cluster_name (same naming convention
  # the eks module itself uses internally) — referencing module.eks's output
  # here would create a cycle, since module.eks below needs the bastion's
  # IAM role ARN for its own access_entries.
  cluster_name = "${local.environment}-eks"
  aws_region   = var.aws_region
  tags         = var.tags
}

module "eks" {
  source              = "./modules/eks"
  environment         = local.environment
  vpc_id              = module.vpc.vpc_id
  private_subnets     = module.vpc.private_subnets
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
  node_instance_types = var.node_instance_types
  use_ubuntu_ami      = var.use_ubuntu_ami
  ubuntu_ami_ssm_path = var.ubuntu_ami_ssm_path
  admin_principal_arns = concat(
    var.eks_admin_principal_arns,
    var.enable_bastion ? [module.bastion.role_arn] : []
  )
  bastion_security_group_id = var.enable_bastion ? module.bastion.security_group_id : ""
  tags                      = var.tags
}

module "eks_addons" {
  source            = "./modules/eks-addons"
  environment       = local.environment
  oidc_provider_arn = module.eks.oidc_provider_arn
  tags              = var.tags
}

module "s3" {
  source      = "./modules/s3"
  bucket_name = var.s3_bucket_name
  kms_key_arn = module.kms.key_arn
  tags        = var.tags
}

module "dynamodb" {
  source      = "./modules/dynamodb"
  environment = local.environment
  tables      = local.dynamodb_tables
  kms_key_arn = module.kms.key_arn
  tags        = var.tags
}

module "iam_irsa" {
  source                     = "./modules/iam"
  environment                = local.environment
  services                   = local.services
  oidc_provider_arn          = module.eks.oidc_provider_arn
  secret_arns                = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:procurement/${local.environment}/*"]
  dynamodb_tables            = values(module.dynamodb.table_names)
  s3_bucket_arn              = module.s3.bucket_arn
  kms_key_arn                = module.kms.key_arn
  aws_region                 = var.aws_region
  bedrock_text_model_id      = var.bedrock_text_model_id
  bedrock_embedding_model_id = var.bedrock_embedding_model_id
}

module "sns" {
  source      = "./modules/sns"
  environment = local.environment
  kms_key_arn = module.kms.key_arn
}

module "lambda_alerts" {
  source                  = "./modules/lambda"
  environment             = local.environment
  sender_email            = var.sns_sender_email
  recipient_email         = var.sns_recipient_email
  sns_topic_arn           = module.sns.topic_arn
  ses_sender_identity_arn = var.create_global_resources ? module.ses[0].sender_identity_arn : var.ses_sender_identity_arn
  tags                    = var.tags
}

resource "aws_sns_topic_subscription" "lambda_alerts" {
  topic_arn = module.sns.topic_arn
  protocol  = "lambda"
  endpoint  = module.lambda_alerts.lambda_function_arn
}

module "cloudwatch" {
  source               = "./modules/cloudwatch"
  environment          = local.environment
  services             = local.services
  sns_topic_arn        = module.sns.topic_arn
  dynamodb_table_names = values(module.dynamodb.table_names)
  eks_cluster_name     = module.eks.cluster_name
  kms_key_arn          = module.kms.key_arn
  tags                 = var.tags
}

module "waf" {
  source      = "./modules/waf"
  environment = local.environment
  enabled     = var.enable_cloudfront
}

module "cloudfront" {
  source              = "./modules/cloudfront"
  enabled             = var.enable_cloudfront
  environment         = local.environment
  alb_dns_name        = var.alb_dns_name
  domain_name         = var.cloudfront_domain_name != "" ? var.cloudfront_domain_name : var.app_hostname
  acm_certificate_arn = var.acm_certificate_arn
  route53_zone_id     = var.route53_zone_id
  web_acl_id          = module.waf.web_acl_arn
  tags                = var.tags
}

module "ecr" {
  count    = var.create_global_resources ? 1 : 0
  source   = "./modules/ecr"
  services = local.services
  tags     = var.tags
}

module "ses" {
  count           = var.create_global_resources ? 1 : 0
  source          = "./modules/ses"
  sender_email    = var.sns_sender_email
  recipient_email = var.sns_recipient_email
}

module "route53" {
  count       = var.create_global_resources ? 1 : 0
  source      = "./modules/route53"
  domain_name = var.domain_name
  tags        = var.tags
}

module "acm" {
  count       = var.create_global_resources ? 1 : 0
  source      = "./modules/acm"
  domain_name = var.domain_name
  zone_id     = module.route53[0].zone_id
  tags        = var.tags
}

module "github_oidc_provider" {
  count  = var.create_global_resources ? 1 : 0
  source = "./modules/github-oidc-provider"
  tags   = var.tags
}

data "aws_iam_policy_document" "ci_app_policy" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = ["arn:aws:ecr:*:*:repository/procurement-*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::procurement-tf-state-global",
      "arn:aws:s3:::procurement-tf-state-global/*",
    ]
  }
  statement {
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

module "github_oidc_role_app" {
  count             = var.create_global_resources ? 1 : 0
  source            = "./modules/github-oidc-role"
  oidc_provider_arn = module.github_oidc_provider[0].provider_arn
  github_repo       = var.github_repo_app
  role_name         = "github-actions-ci-app-role"
  policy_json       = data.aws_iam_policy_document.ci_app_policy.json
  tags              = var.tags
}

data "aws_iam_policy_document" "ci_infra_policy" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "eks:DescribeCluster",
      "eks:ListClusters",
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::procurement-tf-state-global",
      "arn:aws:s3:::procurement-tf-state-global/*",
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = ["arn:aws:dynamodb:*:*:table/terraform-state-lock"]
  }
  statement {
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

module "github_oidc_role_infra" {
  count             = var.create_global_resources ? 1 : 0
  source            = "./modules/github-oidc-role"
  oidc_provider_arn = module.github_oidc_provider[0].provider_arn
  github_repo       = var.github_repo_infra
  role_name         = "github-actions-ci-infra-role"
  policy_json       = data.aws_iam_policy_document.ci_infra_policy.json
  tags              = var.tags
}

resource "aws_iam_role_policy_attachment" "infra_admin_for_apply" {
  count      = var.create_global_resources ? 1 : 0
  role       = module.github_oidc_role_infra[0].role_name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
