aws_region = "us-east-1"

vpc_cidr            = "10.1.0.0/16"
azs                 = ["us-east-1a", "us-east-1b"]
private_subnets     = ["10.1.1.0/24", "10.1.2.0/24"]
public_subnets      = ["10.1.101.0/24", "10.1.102.0/24"]
node_min_size       = 1
node_max_size       = 3
node_desired_size   = 2
node_instance_types = ["t3.medium"]
s3_bucket_name      = "procurement-documents-prod-08"
app_hostname        = "procurement.procure-flow.online"

bedrock_text_model_id      = "amazon.nova-pro-v1:0"
bedrock_embedding_model_id = "amazon.nova-2-multimodal-embeddings-v1:0"

sns_sender_email    = "kondojuvinaykumar2004@gmail.com"
sns_recipient_email = "307372@ust.com"

# Only used when create_global_resources = true (applied once, alongside whichever
# workspace's first apply you choose to hold the account-level singletons).
domain_name       = "procure-flow.online"
github_repo_app   = "ProcurementPlatform/procurement-platform-app"
github_repo_infra = "ProcurementPlatform/procurement-platform-infra"

# Always gets cluster-admin EKS access, regardless of who last ran apply.
eks_admin_principal_arns = ["arn:aws:iam::919010206859:user/rootVinay"]

# CloudFront/bastion deliberately OFF for now — VPC/EKS are being destroyed
# for cost savings until the next review. Re-enabling requires a fresh
# alb_dns_name (the old NLB no longer exists once EKS is recreated):
#   1. terraform apply  (this file, as-is — brings back VPC/EKS only)
#   2. ./scripts/create-secrets.sh prod && ./scripts/bootstrap-cluster.sh prod
#      (prints the exact next command with the new NLB hostname filled in)
#   3. Run that printed command, or set enable_cloudfront/enable_bastion =
#      true here with the fresh alb_dns_name and re-apply.
enable_cloudfront   = false
enable_bastion      = false
acm_certificate_arn = "arn:aws:acm:us-east-1:919010206859:certificate/7b27e59d-f495-4690-a7b5-4de8d21857c9"
route53_zone_id     = "Z02726083CKNR3VSHFFNT"

tags = {
  Environment = "prod"
  Project     = "Procurement-Platform"
  Owner       = "Vinay"
  ManagedBy   = "Terraform"
}
