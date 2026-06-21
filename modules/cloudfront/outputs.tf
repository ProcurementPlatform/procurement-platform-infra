output "distribution_domain_name" {
  value = var.enabled ? aws_cloudfront_distribution.frontend[0].domain_name : null
}
output "distribution_id" {
  value = var.enabled ? aws_cloudfront_distribution.frontend[0].id : null
}
