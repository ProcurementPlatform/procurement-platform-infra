output "irsa_role_arns" {
  value = { for k, v in module.irsa : k => v.iam_role_arn }
}
