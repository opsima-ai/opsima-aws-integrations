output "opsima_remote_access_role_arn" {
  description = "ARN of OpsimaRemoteAccessRole, the role Opsima assumes in your Management Account."
  value       = aws_iam_role.opsima_remote_access.arn
}

output "handle_opsima_accounts_lambda_arn" {
  description = "ARN of the HandleOpsimaAccounts Lambda function invoked by Opsima."
  value       = aws_lambda_function.handle_opsima_accounts.arn
}
