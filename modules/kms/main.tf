data "aws_caller_identity" "current" {}

# CloudWatch Logs and SNS both require an explicit key-policy grant for their
# service principal to use a customer-managed CMK — unlike S3/DynamoDB, IAM
# permissions on the calling principal alone aren't enough for these two.
# Without this, the SNS topic / CloudWatch log group encryption added for the
# tfsec findings would fail at apply time with AccessDenied.
data "aws_iam_policy_document" "key_policy" {
  statement {
    sid       = "EnableIAMUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowSNS"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "key" {
  description         = "KMS key for ${var.environment}"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.key_policy.json
  tags                = var.tags
}

resource "aws_kms_alias" "alias" {
  name          = "alias/procurement-${var.environment}"
  target_key_id = aws_kms_key.key.key_id
}
