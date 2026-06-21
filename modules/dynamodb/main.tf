resource "aws_dynamodb_table" "app_table" {
  for_each     = var.tables
  name         = "${var.environment}-${each.key}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "_id"

  attribute {
    name = "_id"
    type = "S"
  }

  dynamic "attribute" {
    for_each = each.value
    content {
      name = attribute.value.attribute_name
      type = "S"
    }
  }

  dynamic "global_secondary_index" {
    for_each = each.value
    content {
      name            = global_secondary_index.value.index_name
      hash_key        = global_secondary_index.value.attribute_name
      projection_type = "ALL"
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = var.tags
}
