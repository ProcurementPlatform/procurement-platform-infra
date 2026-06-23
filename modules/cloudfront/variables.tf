variable "enabled" { type = bool }
variable "environment" { type = string }
variable "alb_dns_name" { type = string }
variable "domain_name" { type = string }
variable "acm_certificate_arn" { type = string }
variable "route53_zone_id" { type = string }
variable "web_acl_id" { type = string }
variable "tags" { type = map(string) }
