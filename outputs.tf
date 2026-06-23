output "aws_region" { value = var.aws_region }
output "eks_cluster_name" { value = module.eks.cluster_name }
output "eks_cluster_endpoint" { value = module.eks.cluster_endpoint }
output "eks_oidc_provider_arn" { value = module.eks.oidc_provider_arn }
output "eks_lbc_role_arn" { value = module.eks.lbc_role_arn }
output "eks_ebs_csi_role_arn" { value = module.eks_addons.ebs_csi_role_arn }
output "vpc_id" { value = module.vpc.vpc_id }
output "irsa_role_arns" { value = module.iam_irsa.irsa_role_arns }
output "dynamodb_table_names" { value = module.dynamodb.table_names }
output "s3_bucket_name" { value = module.s3.bucket_name }
output "s3_bucket_arn" { value = module.s3.bucket_arn }
output "kms_key_arn" { value = module.kms.key_arn }
output "waf_web_acl_arn" { value = module.waf.web_acl_arn }
output "sns_topic_arn" { value = module.sns.topic_arn }
output "cloudfront_domain_name" { value = module.cloudfront.distribution_domain_name }
output "app_hostname" { value = var.app_hostname }
output "bedrock_text_model_id" { value = var.bedrock_text_model_id }
output "bedrock_embedding_model_id" { value = var.bedrock_embedding_model_id }
output "secrets_name_prefix" { value = "procurement/${local.environment}" }

output "ecr_repository_urls" {
  value = var.create_global_resources ? module.ecr[0].repository_urls : null
}
output "ses_sender_identity_arn" {
  value = var.create_global_resources ? module.ses[0].sender_identity_arn : null
}
output "route53_zone_id" {
  value = var.create_global_resources ? module.route53[0].zone_id : null
}
output "acm_certificate_arn" {
  value = var.create_global_resources ? module.acm[0].certificate_arn : null
}
output "github_oidc_app_role_arn" {
  value = var.create_global_resources ? module.github_oidc_role_app[0].role_arn : null
}
output "github_oidc_infra_role_arn" {
  value = var.create_global_resources ? module.github_oidc_role_infra[0].role_arn : null
}
