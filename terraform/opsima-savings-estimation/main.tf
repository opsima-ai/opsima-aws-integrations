resource "aws_iam_role" "opsima_limited_access" {
  name        = "OpsimaLimitedAccessRole"
  description = "Role assumed by Opsima to work within the above permissions"

  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${var.opsima_principal}:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "${var.external_id}"
        }
      }
    }
  ]
}
EOT

  tags = {
    owner = "opsima"
  }
}

resource "aws_iam_role_policy" "opsima_limited_access" {
  name = "OpsimaLimitedAccessRolePolicy"
  role = aws_iam_role.opsima_limited_access.name

  policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CostExplorerReadAccess",
      "Effect": "Allow",
      "Action": [
        "ce:GetSavingsPlansCoverage",
        "ce:GetSavingsPlansUtilization",
        "ce:GetReservationCoverage",
        "ce:GetReservationUtilization",
        "ce:GetCostAndUsage",
        "ce:GetDimensionValues"
      ],
      "Resource": "*"
    }
  ]
}
EOT
}
