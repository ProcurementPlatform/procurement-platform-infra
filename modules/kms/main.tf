data "aws_caller_identity" "current" {}

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
      type = "Service"
      # sns.amazonaws.com covers SNS's own delivery to subscribers (e.g. Lambda).
      # cloudwatch.amazonaws.com is also required: CloudWatch Alarms call
      # sns:Publish directly, and publishing into a KMS-encrypted topic needs
      # the calling service principal (not just SNS itself) granted decrypt /
      # generate-data-key — without it, alarm_actions silently fail.
      identifiers = ["sns.amazonaws.com", "cloudwatch.amazonaws.com"]
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
