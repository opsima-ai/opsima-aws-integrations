data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "opsima-cur-${var.customer_short_id}"
  create_ou   = var.create_opsima_organizational_unit
  ou_id       = local.create_ou ? aws_organizations_organizational_unit.opsima[0].id : var.opsima_organizational_unit_id

  lambda_function_name = "HandleOpsimaAccounts"

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

resource "aws_iam_role" "handle_opsima_accounts_lambda" {
  name        = "HandleOpsimaAccountsLambdaExecutionRole"
  description = "Execution role for HandleOpsimaAccounts Lambda function"
  tags        = local.tags

  assume_role_policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "${local.account_id}"
        },
        "ArnLike": {
          "aws:SourceArn": "arn:aws:lambda:${data.aws_region.current.region}:${local.account_id}:function:${local.lambda_function_name}"
        }
      }
    }
  ]
}
EOT
}

resource "aws_cloudwatch_log_group" "handle_opsima_accounts_lambda" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 365
  tags              = local.tags
}

resource "aws_iam_role_policy" "handle_opsima_accounts_lambda" {
  name = "HandleOpsimaAccountsLambdaPolicy"
  role = aws_iam_role.handle_opsima_accounts_lambda.name

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
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${data.aws_region.current.region}:${local.account_id}:log-group:/aws/lambda/${local.lambda_function_name}:*"
    },
    {
      "Sid": "AllowOrganizationCreateAccountStatus",
      "Effect": "Allow",
      "Action": "organizations:DescribeCreateAccountStatus",
      "Resource": "*"
    },
    {
      "Sid": "AllowOrganizationTagOpsimaAccounts",
      "Effect": "Allow",
      "Action": "organizations:TagResource",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/owner": "opsima",
          "aws:RequestTag/role": "OpsimaOrganizationAccountAccessRole"
        },
        "ForAllValues:StringEquals": {
          "aws:TagKeys": ["owner", "role"]
        }
      }
    },
    {
      "Sid": "AllowOrganizationCreateInviteAccount",
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
      "Sid": "AllowAssumeOpsimaRoleInInvitedAccounts",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::*:role/OpsimaOrganizationAccountAccessRole",
      "Condition": {
        "StringEquals": {
          "aws:ResourceOrgID": "${var.opsima_organization_id}"
        }
      }
    }
  ]
}
EOT
}

resource "aws_lambda_function" "handle_opsima_accounts" {
  function_name = local.lambda_function_name
  description   = "Lambda function to handle Opsima accounts operations (CREATE, INVITE)"
  role          = aws_iam_role.handle_opsima_accounts_lambda.arn
  runtime       = "nodejs24.x"
  handler       = "handleOpsimaAccounts.handler"
  timeout       = 300
  memory_size   = 256
  tags          = local.tags

  reserved_concurrent_executions = 1

  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "INFO"
    log_group             = aws_cloudwatch_log_group.handle_opsima_accounts_lambda.name
  }

  # Deploy either a locally built package (lambda_filename) or the released package from the Opsima bucket.
  filename         = var.lambda_filename
  s3_bucket        = var.lambda_filename == null ? var.lambda_s3_bucket : null
  s3_key           = var.lambda_filename == null ? var.lambda_s3_key : null
  source_code_hash = var.lambda_filename != null ? filebase64sha256(var.lambda_filename) : var.lambda_source_code_hash

  lifecycle {
    precondition {
      condition     = var.lambda_filename != null || data.aws_region.current.region == "eu-west-1"
      error_message = "The released Lambda package is hosted in eu-west-1; deploy in eu-west-1 or set lambda_filename to a locally built package."
    }
  }

  environment {
    variables = {
      OPSIMA_OU_ID                 = local.ou_id
      ORGANIZATION_ID              = var.organization_id
      ORGANIZATION_ROOT_ID         = var.organization_root_id
      OPSIMA_ORGANIZATION_ID       = var.opsima_organization_id
      OPSIMA_MANAGEMENT_ACCOUNT_ID = var.opsima_management_account_id
    }
  }

  depends_on = [
    aws_iam_role_policy.handle_opsima_accounts_lambda,
    aws_cloudwatch_log_group.handle_opsima_accounts_lambda,
  ]
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

resource "aws_iam_role_policy" "opsima_remote_access" {
  name = "OpsimaRemoteAccessRolePolicy"
  role = aws_iam_role.opsima_remote_access.name

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
        "organizations:ListAccounts",
        "organizations:ListTagsForResource",
        "invoicing:CreateInvoiceUnit",
        "invoicing:GetInvoiceUnit",
        "invoicing:UpdateInvoiceUnit",
        "invoicing:TagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowAssumeRole",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::*:role/OpsimaOrganizationAccountAccessRole",
      "Condition": {
        "StringEquals": {
          "aws:ResourceOrgID": "${var.organization_id}"
        }
      }
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
      "Sid": "AllowInvokeHandleOpsimaAccountsLambda",
      "Effect": "Allow",
      "Action": "lambda:InvokeFunction",
      "Resource": "${aws_lambda_function.handle_opsima_accounts.arn}"
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
