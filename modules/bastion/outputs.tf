output "role_arn" {
  value = var.enabled ? aws_iam_role.bastion[0].arn : null
}
output "instance_id" {
  value = var.enabled ? aws_instance.bastion[0].id : null
}
output "security_group_id" {
  value = var.enabled ? aws_security_group.bastion[0].id : null
}
