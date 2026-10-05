# Opsima AWS integrations

Infrastructure-as-code and source that Opsima customers deploy in their AWS Organization to integrate
with Opsima. Everything a customer runs in their own Management Account is in this repository, versioned
and released so that it can be reviewed, built and pinned before deployment.

## What is deployed

| Need | Terraform module | CloudFormation template | What it creates |
|---|---|---|---|
| Commitment management (default) | [`terraform/opsima-remote-access`](terraform/opsima-remote-access) | [`opsima-cloud_formation-full_access_lambda.yaml`](cloudformation/opsima-cloud_formation-full_access_lambda.yaml) | `OpsimaRemoteAccessRole`, the `HandleOpsimaAccounts` Lambda function and its execution role, the Opsima OU, the CUR bucket |
| Commitment management, IAM only | [`terraform/opsima-remote-access-iam`](terraform/opsima-remote-access-iam) | [`opsima-cloud_formation-full_access.yaml`](cloudformation/opsima-cloud_formation-full_access.yaml) | Same without the Lambda function: `OpsimaRemoteAccessRole` holds the account-management permissions itself |
| Savings estimation (read-only) | [`terraform/opsima-savings-estimation`](terraform/opsima-savings-estimation) | [`opsima-cloud_formation-limited_access.yaml`](cloudformation/opsima-cloud_formation-limited_access.yaml) | `OpsimaLimitedAccessRole` with Cost Explorer read access |

The service control policy to attach to the Opsima OU is in [`scp/`](scp/).

## How it works

Opsima manages Savings Plans and Reserved Instances on your behalf from dedicated accounts placed in an
Organizational Unit of your Organization, governed by the SCP you attach to it. Accounts are created by
the Lambda function, or transferred from another customer through the Opsima Organization when
commitments can be reassigned.

## Releases

Each release is a Git tag and a GitHub Release. The Terraform modules, CloudFormation templates and SCP
are used straight from the tag. Only the Lambda function is distributed as a built artefact: its zip and
SHA-256 are attached to the GitHub Release. Changes are listed in [CHANGELOG.md](CHANGELOG.md).

With Terraform, the function is deployed from a local file (`lambda_filename`): build it from the tag, or
download it from the GitHub Release, and compare its SHA-256 with the published one; see the module and
Lambda READMEs. The CloudFormation template loads the package from the Opsima public bucket.

## Security

See [SECURITY.md](SECURITY.md) to report a vulnerability. Opsima's security documentation is available
at https://trust.opsima.ai.

## License

[Apache License 2.0](LICENSE).
