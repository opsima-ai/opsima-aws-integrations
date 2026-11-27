data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_arn  = "arn:aws:s3:::${var.cur_bucket_name}"
  objects_arn = var.cur_bucket_prefix == "" ? "${local.bucket_arn}/*" : "${local.bucket_arn}/${var.cur_bucket_prefix}/*"

  tags = {
    owner = "opsima"
  }
}

resource "aws_iam_role" "opsima_cur_access" {
  name        = "OpsimaCurAccessRole"
  description = "Role assumed by Opsima to read the ${var.cur_export_name} Cost and Usage Report"
  tags        = local.tags

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
        },
        "ArnEquals": {
          "aws:PrincipalArn": "arn:aws:iam::${var.opsima_principal}:role/OpsimaRemoteAccessRole"
        }
      }
    }
  ]
}
EOT
}

resource "aws_iam_role_policy" "opsima_cur_access" {
  name = "OpsimaCurAccessRolePolicy"
  role = aws_iam_role.opsima_cur_access.name

  policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowListDataExports",
      "Effect": "Allow",
      "Action": "bcm-data-exports:ListExports",
      "Resource": "*"
    },
    {
      "Sid": "AllowReadCurExport",
      "Effect": "Allow",
      "Action": [
        "bcm-data-exports:GetExport",
        "bcm-data-exports:GetExecution",
        "bcm-data-exports:ListExecutions"
      ],
      "Resource": "arn:aws:bcm-data-exports:*:${local.account_id}:export/${var.cur_export_name}-*"
    },
    {
      "Sid": "AllowGetCurBucketLocation",
      "Effect": "Allow",
      "Action": "s3:GetBucketLocation",
      "Resource": "${local.bucket_arn}"
    },
    {
      "Sid": "AllowListCurBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "${local.bucket_arn}"%{if var.cur_bucket_prefix != ""},
      "Condition": {
        "StringLike": {
          "s3:prefix": [
            "${var.cur_bucket_prefix}",
            "${var.cur_bucket_prefix}/*"
          ]
        }
      }%{endif}
    },
    {
      "Sid": "AllowReadCurObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "${local.objects_arn}"
    }
  ]
}
EOT
}
