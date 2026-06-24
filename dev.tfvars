aws_region = "us-east-1"

vpc_cidr            = "10.0.0.0/16"
azs                 = ["us-east-1a", "us-east-1b"]
private_subnets     = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnets      = ["10.0.101.0/24", "10.0.102.0/24"]
node_min_size       = 1
node_max_size       = 3
node_desired_size   = 2
node_instance_types = ["t3.medium"]
s3_bucket_name      = "procurement-documents-dev-08"
app_hostname        = "procurement-dev.procure-flow.online"

bedrock_text_model_id      = "amazon.nova-pro-v1:0"
bedrock_embedding_model_id = "amazon.nova-2-multimodal-embeddings-v1:0"

sns_sender_email    = "kondojuvinaykumar2004@gmail.com"
sns_recipient_email = "307372@ust.com"

domain_name       = "procure-flow.online"
github_repo_app   = "ProcurementPlatform/procurement-platform-app"
github_repo_infra = "ProcurementPlatform/procurement-platform-infra"

eks_admin_principal_arns = ["arn:aws:iam::919010206859:user/rootVinay"]

tags = {
  Environment = "dev"
  Project     = "Procurement-Platform"
  Owner       = "Vinay"
  ManagedBy   = "Terraform"
}
