variable "environment" {
  type = string
}

variable "enabled" {
  type        = bool
  description = "Only create the WAF when CloudFront is enabled — a CLOUDFRONT-scope WAF has nothing to attach to otherwise."
}
