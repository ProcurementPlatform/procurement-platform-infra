module "irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  for_each = toset(var.services)

  role_name = "${var.environment}-${each.value}-irsa"

  oidc_providers = {
    ex = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["procurement-${var.environment}:${each.value}"]
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.irsa_policy[each.key].arn
  }
}

resource "aws_iam_policy" "irsa_policy" {
  for_each    = toset(var.services)
  name        = "${var.environment}-${each.value}-policy"
  description = "IRSA policy for ${each.value}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Effect   = "Allow"
        Resource = [for arn in var.secret_arns : arn]
      },
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Effect = "Allow"
        Resource = concat(
          [for t in var.dynamodb_tables : "arn:aws:dynamodb:*:*:table/${t}"],
          [for t in var.dynamodb_tables : "arn:aws:dynamodb:*:*:table/${t}/index/*"]
        )
      },
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      },
      {
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Effect   = "Allow"
        Resource = [var.kms_key_arn]
      }
    ]
  })
}
