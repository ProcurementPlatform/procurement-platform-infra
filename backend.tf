terraform {
  backend "s3" {
    key = "procurement-platform/terraform.tfstate"
  }
}
