locals {
  # Maps the long service identifiers used everywhere else in Terraform/Helm/IRSA
  # (frontend, identity-service, ...) to the SHORT repo names already created by
  # scripts/ecr-push.sh and in active use (procurement-identity, procurement-ai, ...).
  repo_short_name = {
    frontend              = "frontend"
    "identity-service"    = "identity"
    "procurement-service" = "procurement"
    "finance-service"     = "finance"
    "document-service"    = "document"
    "ai-service"          = "ai"
  }
}

resource "aws_ecr_repository" "repo" {
  for_each             = toset(var.services)
  name                 = "procurement-${local.repo_short_name[each.value]}"
  image_tag_mutability = "MUTABLE"

  lifecycle {
    prevent_destroy = true
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "retain_recent" {
  for_each   = aws_ecr_repository.repo
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
