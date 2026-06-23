locals {
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

  encryption_configuration {
    encryption_type = "KMS"
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
