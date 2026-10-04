output "opsima_remote_access_role_arn" {
  description = "IAM Remote Access Role ARN used by Opsima"
  value       = aws_iam_role.opsima_remote_access.arn
}

output "opsima_organizational_unit_id" {
  description = "Organizational Unit ID where Opsima managed accounts are placed"
  value       = local.ou_id
}
