output "opsima_limited_access_role_arn" {
  description = "IAM Limited Access Role ARN used by Opsima"
  value       = aws_iam_role.opsima_limited_access.arn
}
