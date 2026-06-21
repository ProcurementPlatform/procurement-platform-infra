variable "oidc_provider_arn" { type = string }
variable "github_repo" {
  description = "owner/repo, e.g. ProcurementPlatform/procurement-platform-app"
  type        = string
}
variable "role_name" { type = string }
variable "policy_json" { type = string }
variable "tags" { type = map(string) }
