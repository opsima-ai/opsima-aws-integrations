data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "opsima-cur-${var.customer_short_id}"
  create_ou   = var.create_opsima_organizational_unit
  ou_id       = local.create_ou ? aws_organizations_organizational_unit.opsima[0].id : var.opsima_organizational_unit_id

  tags = {
    owner = "opsima"
  }
}

resource "aws_s3_bucket" "cur" {
  count = var.create_cur_bucket ? 1 : 0

  bucket = local.bucket_name
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "cur" {
  count = var.create_cur_bucket ? 1 : 0

  bucket = aws_s3_bucket.cur[0].id
  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_public_access_block" "cur" {
  count = var.create_cur_bucket ? 1 : 0

  bucket                  = aws_s3_bucket.cur[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cur" {
  count = var.create_cur_bucket ? 1 : 0

  bucket = aws_s3_bucket.cur[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cur" {
  count = var.create_cur_bucket ? 1 : 0

  bucket = aws_s3_bucket.cur[0].id
  rule {
    id     = "expire-cur-reports"
    status = "Enabled"
    filter {}
    expiration {
      days = 1130
    }
  }
}

resource "aws_s3_bucket_policy" "cur" {
  count = var.create_cur_bucket ? 1 : 0

  bucket = aws_s3_bucket.cur[0].id
  policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransportAll",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "${aws_s3_bucket.cur[0].arn}",
        "${aws_s3_bucket.cur[0].arn}/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    },
    {
      "Sid": "AllowBCMDataExportsServiceWriteObjects",
      "Effect": "Allow",
      "Principal": {
        "Service": "bcm-data-exports.amazonaws.com"
      },
      "Action": [
        "s3:PutObject",
        "s3:GetBucketAcl",
        "s3:GetBucketPolicy"
      ],
      "Resource": [
        "${aws_s3_bucket.cur[0].arn}",
        "${aws_s3_bucket.cur[0].arn}/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "${local.account_id}"
        },
        "ArnLike": {
          "aws:SourceArn": "arn:aws:bcm-data-exports:*:${local.account_id}:export/*"
        }
      }
    }
  ]
}
EOT
}

resource "aws_organizations_organizational_unit" "opsima" {
  count = local.create_ou ? 1 : 0

  name      = "opsima-${var.customer_short_id}"
  parent_id = var.organization_root_id
  tags      = local.tags

  lifecycle {
    precondition {
      condition     = var.opsima_organizational_unit_id == ""
      error_message = "opsima_organizational_unit_id is set: also set create_opsima_organizational_unit = false to use your own Organizational Unit."
    }
  }
}

resource "aws_iam_role" "opsima_remote_access" {
  name        = "OpsimaRemoteAccessRole"
  description = "Role assumed by Opsima to work within the above permissions"
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
        }
      }
    }
  ]
}
EOT
}

resource "aws_iam_role_policy" "opsima_remote_access" {
  name = "OpsimaRemoteAccessRolePolicy"
  role = aws_iam_role.opsima_remote_access.name

  lifecycle {
    precondition {
      condition     = var.create_opsima_organizational_unit || var.opsima_organizational_unit_id != ""
      error_message = "create_opsima_organizational_unit is false: set opsima_organizational_unit_id to the Organizational Unit hosting Opsima accounts."
    }
  }

  policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOpsimaCoreOperations",
      "Effect": "Allow",
      "Action": [
        "bcm-data-exports:CreateExport",
        "bcm-data-exports:TagResource",
        "bcm-data-exports:ListExports",
        "bcm-data-exports:GetExport",
        "ce:GetSavingsPlansCoverage",
        "ce:GetSavingsPlansUtilization",
        "ce:GetReservationCoverage",
        "ce:GetReservationUtilization",
        "ce:GetCostAndUsage",
        "ce:GetDimensionValues",
        "cur:PutReportDefinition",
        "cur:DescribeReportDefinitions",
        "cur:TagResource",
        "organizations:TagResource",
        "organizations:ListAccounts",
        "organizations:ListTagsForResource",
        "organizations:DescribeCreateAccountStatus",
        "invoicing:CreateInvoiceUnit",
        "invoicing:GetInvoiceUnit",
        "invoicing:UpdateInvoiceUnit",
        "invoicing:TagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowOrganizationCreateAccount",
      "Effect": "Allow",
      "Action": [
        "organizations:CreateAccount",
        "organizations:InviteAccountToOrganization"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/owner": "opsima"
        }
      }
    },
    {
      "Sid": "AllowOrganizationMoveOpsimaAccount",
      "Effect": "Allow",
      "Action": "organizations:MoveAccount",
      "Resource": "arn:aws:organizations::${local.account_id}:account/${var.organization_id}/*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/owner": "opsima"
        }
      }
    },
    {
      "Sid": "AllowOrganizationMoveOpsimaAccountParents",
      "Effect": "Allow",
      "Action": "organizations:MoveAccount",
      "Resource": [
        "arn:aws:organizations::${local.account_id}:root/*",
        "arn:aws:organizations::${local.account_id}:ou/${var.organization_id}/${local.ou_id}"
      ]
    },
    {
      "Sid": "AllowAssumeRole",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::*:role/OpsimaOrganizationAccountAccessRole"
    },
    {
      "Sid": "AllowCURBucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${local.bucket_name}",
        "arn:aws:s3:::${local.bucket_name}/*"
      ]
    },
    {
      "Sid": "AllowOrganizationsAccountQuotaIncrease",
      "Effect": "Allow",
      "Action": "servicequotas:RequestServiceQuotaIncrease",
      "Resource": "arn:aws:servicequotas::${local.account_id}:organizations/L-E619E033"
    }
  ]
}
EOT
}
