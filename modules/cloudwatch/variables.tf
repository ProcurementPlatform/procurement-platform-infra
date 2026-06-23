variable "environment" { type = string }
variable "tags" { type = map(string) }
variable "kms_key_arn" { type = string }
variable "services" { type = list(string) }
variable "sns_topic_arn" { type = string }
variable "dynamodb_table_names" { type = list(string) }

variable "alb_arn_suffix" {
  type    = string
  default = ""
}

variable "eks_cluster_name" {
  type    = string
  default = ""
}
