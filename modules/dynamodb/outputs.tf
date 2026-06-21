output "table_names" {
  value = { for k, v in aws_dynamodb_table.app_table : k => v.name }
}
