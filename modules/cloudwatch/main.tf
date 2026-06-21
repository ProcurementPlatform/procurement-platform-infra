# No aws_cloudwatch_log_group "eks" here on purpose: the EKS module enables
# control plane logging (cluster_enabled_log_types defaults to
# ["audit","api","authenticator"]), which makes AWS's EKS service itself the
# permanent owner of /aws/eks/<cluster>/cluster — it auto-creates/recreates
# that log group on its own. Terraform trying to also manage it collides with
# that ownership (confirmed via CloudTrail: an EKS-internal identity, not us,
# created it mid-apply). Retention for it can only be set via the AWS-side
# default or a one-off `aws logs put-retention-policy` if needed.

resource "aws_cloudwatch_log_group" "service" {
  for_each          = toset(var.services)
  name              = "/eks/${var.environment}/${each.value}"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count               = var.alb_arn_suffix != "" ? 1 : 0
  alarm_name          = "${var.environment}-alb-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_actions       = [var.sns_topic_arn]
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "node_cpu_high" {
  count               = var.eks_cluster_name != "" ? 1 : 0
  alarm_name          = "${var.environment}-eks-node-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [var.sns_topic_arn]
  dimensions          = { ClusterName = var.eks_cluster_name }
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_errors" {
  for_each            = toset(var.dynamodb_table_names)
  alarm_name          = "${var.environment}-dynamodb-${each.value}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_actions       = [var.sns_topic_arn]
  dimensions          = { TableName = each.value }
  tags                = var.tags
}
