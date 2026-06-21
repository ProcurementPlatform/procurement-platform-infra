resource "aws_kms_key" "key" {
  description         = "KMS key for ${var.environment}"
  enable_key_rotation = true
  tags                = var.tags
}

resource "aws_kms_alias" "alias" {
  name          = "alias/procurement-${var.environment}"
  target_key_id = aws_kms_key.key.key_id
}
