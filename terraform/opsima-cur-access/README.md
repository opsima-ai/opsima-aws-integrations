# opsima-cur-access

Read access to an existing Cost and Usage Report (read-only). Creates `OpsimaCurAccessRole`, a role that can
only describe one Data Exports export and read its objects in S3. Nothing is created or modified on the
export or the bucket.

Deploy in the Management Account of your Organization, the account that owns both the export and the bucket.

## Usage

```hcl
provider "aws" {
  region = "eu-west-1"
}

module "opsima_cur" {
  source = "git::https://github.com/opsima-ai/opsima-aws-integrations.git//terraform/opsima-cur-access?ref=v11.1.0-rc.1"

  # Values provided by Opsima
  external_id = var.opsima_external_id

  # Your existing export
  cur_export_name   = "my-cur2_0"
  cur_bucket_name   = "my-cur-bucket"
  cur_bucket_prefix = "CUR2"
  # see variables.tf for the full list
}
```

Values can also be supplied through a `terraform.tfvars` file when the module is applied directly; see
`terraform.tfvars.example`. Every input is documented and validated in `variables.tf`; outputs are in
`outputs.tf`.

## Permissions granted

| Scope | Actions |
|-------|---------|
| All exports of the account | `bcm-data-exports:ListExports` (listing has no resource-level permission) |
| The export named `cur_export_name` | `bcm-data-exports:GetExport`, `bcm-data-exports:GetExecution`, `bcm-data-exports:ListExecutions` |
| The bucket `cur_bucket_name` | `s3:GetBucketLocation`, `s3:ListBucket` (limited to `cur_bucket_prefix` when set) |
| Objects under `cur_bucket_prefix` | `s3:GetObject`, `s3:GetObjectVersion` |
