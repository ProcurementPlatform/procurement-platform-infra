variable "aws_region" { type = string }
variable "tags" { type = map(string) }

# --- Environment-scoped (set per workspace via dev.tfvars / prod.tfvars) ---
variable "vpc_cidr" { type = string }
variable "azs" { type = list(string) }
variable "private_subnets" { type = list(string) }
variable "public_subnets" { type = list(string) }
variable "node_min_size" { type = number }
variable "node_max_size" { type = number }
variable "node_desired_size" { type = number }
variable "node_instance_types" { type = list(string) }
variable "use_ubuntu_ami" {
  description = "Use Canonical's Ubuntu EKS-optimized AMI instead of the default Amazon Linux. Defaults off — verify the SSM parameter resolves in your account/region before turning this on (see modules/eks/main.tf comment). Getting this wrong is the most likely way to hang the node group like the AL2 incident did."
  type        = bool
  default     = false
}
variable "ubuntu_ami_ssm_path" {
  description = "SSM parameter path for the Ubuntu EKS AMI. Only used when use_ubuntu_ami = true."
  type        = string
  default     = "/aws/service/canonical/ubuntu/eks/22.04/1.30/stable/current/amd64/hvm/ebs-gp2/ami-id"
}
variable "eks_admin_principal_arns" {
  description = "IAM principal ARNs (your own user/role) that always get a permanent cluster-admin EKS access entry, never displaced by whichever identity (local user or CI role) last ran terraform apply."
  type        = list(string)
  default     = []
}
variable "s3_bucket_name" { type = string }
variable "app_hostname" { type = string }
variable "bedrock_text_model_id" { type = string }
variable "bedrock_embedding_model_id" { type = string }
variable "sns_sender_email" { type = string }
variable "sns_recipient_email" { type = string }

# --- Account-level singletons (only used when create_global_resources = true) ---
variable "create_global_resources" {
  description = "Create account-level singleton resources (ECR, ACM, Route53, GitHub OIDC, SES). Pass true on the first apply of whichever workspace (dev or prod) you want to hold them — never pass true for both."
  type        = bool
  default     = false
}
variable "domain_name" { type = string }
variable "ses_sender_identity_arn" {
  description = "SES sender identity ARN from `terraform output -raw ses_sender_identity_arn` against the workspace that holds create_global_resources=true. Only required in the *other* workspace (the one that didn't create it)."
  type        = string
  default     = ""
}
variable "github_repo_app" {
  description = "owner/repo for the app repo (ECR push CI role trust), e.g. ProcurementPlatform/procurement-platform-app"
  type        = string
}
variable "github_repo_infra" {
  description = "owner/repo for the infra repo (terraform apply CI role trust), e.g. ProcurementPlatform/procurement-platform-infra"
  type        = string
}

# --- CloudFront (phase 2 — only applied after the first GitOps sync has created a real ALB) ---
variable "enable_cloudfront" {
  description = "Turn on once kubectl get ingress shows a real ALB hostname for this workspace's environment. Off by default."
  type        = bool
  default     = false
}
variable "alb_dns_name" {
  description = "ALB hostname from `kubectl get ingress -n procurement-<env>`. Only required when enable_cloudfront = true."
  type        = string
  default     = ""
}
variable "acm_certificate_arn" {
  description = "ACM cert ARN from `terraform output -raw acm_certificate_arn` against the workspace that holds create_global_resources=true. Only required when enable_cloudfront = true."
  type        = string
  default     = ""
}
variable "route53_zone_id" {
  description = "Route53 zone ID from `terraform output -raw route53_zone_id` against the workspace that holds create_global_resources=true. Only required when enable_cloudfront = true."
  type        = string
  default     = ""
}
