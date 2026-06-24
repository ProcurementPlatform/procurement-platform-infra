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

domain_name       = "procure-flow.online"
github_repo_app   = "ProcurementPlatform/procurement-platform-app"
github_repo_infra = "ProcurementPlatform/procurement-platform-infra"

eks_admin_principal_arns = ["arn:aws:iam::919010206859:user/rootVinay"]

enable_cloudfront   = true
enable_bastion      = false
alb_dns_name        = "k8s-procurem-procurem-41a31add54-de60d5f2d1cbaf5b.elb.us-east-1.amazonaws.com"
acm_certificate_arn = "arn:aws:acm:us-east-1:919010206859:certificate/7b27e59d-f495-4690-a7b5-4de8d21857c9"
route53_zone_id     = "Z02726083CKNR3VSHFFNT"

tags = {
  Environment = "prod"
  Project     = "Procurement-Platform"
  Owner       = "Vinay"
  ManagedBy   = "Terraform"
}
