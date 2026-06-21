variable "environment" { type = string }
variable "tags" { type = map(string) }
variable "kms_key_arn" { type = string }
variable "services" { type = list(string) }
variable "sns_topic_arn" { type = string }
variable "dynamodb_table_names" { type = list(string) }

# The ALB is created by the AWS Load Balancer Controller from an Ingress
# resource, not by Terraform, so its ARN suffix isn't known at first apply.
# Leave blank until the cluster's Ingress exists, then re-apply with the real
# value (read via `aws elbv2 describe-load-balancers`) to enable the 5xx alarm.
variable "alb_arn_suffix" {
  type    = string
  default = ""
}

variable "eks_cluster_name" {
  type    = string
  default = ""
}
