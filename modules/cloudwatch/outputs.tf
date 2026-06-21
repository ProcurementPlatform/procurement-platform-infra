output "service_log_group_arns" {
  value = { for k, v in aws_cloudwatch_log_group.service : k => v.arn }
}
