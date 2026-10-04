# opsima-remote-access-iam

Commitment management, IAM only. Same as opsima-remote-access without the Lambda function: OpsimaRemoteAccessRole holds the account-management permissions itself.

Deploy in the Management Account of your Organization. The released Lambda package is hosted in
`eu-west-1`; deploy in that region or build the package yourself (see
[release-verification](../../docs/release-verification.md)).

## Usage

```hcl
provider "aws" {
  region = "eu-west-1"
}

module "opsima" {
  source = "git::https://github.com/opsima-ai/opsima-aws-integrations.git//terraform/opsima-remote-access-iam?ref=v11.0.0"

  # Values provided by Opsima at onboarding
  external_id = var.opsima_external_id
  # see variables.tf for the full list
}
```

Values can also be supplied through a `terraform.tfvars` file when the module is applied directly; see
`terraform.tfvars.example`. Every input is documented and validated in `variables.tf`; outputs are in
`outputs.tf`.
