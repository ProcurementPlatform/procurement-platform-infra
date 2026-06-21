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
  for_each = toset(var.services)
  name     = "procurement-${local.repo_short_name[each.value]}"
  # MUTABLE is required, not a default left unconsidered: build.yml pushes
  # both a content-addressed tag and a rolling `:latest` on every build —
  # IMMUTABLE would reject the repeat `:latest` push every single time.
  image_tag_mutability = "MUTABLE"

  lifecycle {
    # TEMP: false while switching encryption_configuration to KMS — that
    # attribute is immutable on an existing repo, so this one apply replaces
    # all 6 (confirmed empty, 0 images, via `aws ecr list-images` — nothing
    # lost). Revert to true in the very next commit once this lands.
    prevent_destroy = false
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
