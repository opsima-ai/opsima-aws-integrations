output "opsima_cur_access_role_arn" {
  description = "IAM role ARN used by Opsima to read the Cost and Usage Report"
  value       = aws_iam_role.opsima_cur_access.arn
}
