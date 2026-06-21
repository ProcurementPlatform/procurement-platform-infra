# Bucket/region/dynamodb_table are intentionally omitted here — Terraform
# backend blocks can't use variables, so account portability (switching AWS
# accounts means a brand-new, globally-unique bucket name) is handled via
# partial configuration instead. Supply the real values at init time with
# -backend-config flags or a backend.hcl file (see backend.hcl.example).
terraform {
  backend "s3" {
    key = "procurement-platform/terraform.tfstate"
  }
}
