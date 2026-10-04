# Changelog

All notable changes to this repository are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow the CloudFormation stack
version they correspond to.

## [Unreleased]

## [11.0.0]

First public release. Compared with the previously distributed package (stack version 10):

### Lambda
- `INVITE` now performs the whole transfer in one invocation: it assumes the transferred account's Opsima
  role under a restrictive session policy, verifies the account is a member of the Opsima Organization,
  invites it, accepts the invitation on its behalf and moves it into the Opsima OU. No callback to Opsima.
- The account ID is validated, the root ID comes from the `ORGANIZATION_ROOT_ID` variable (no `ListRoots`),
  creation is polled for up to 4 minutes and the move is retried with backoff. The `MOVE` action is removed.
- Runtime `nodejs24.x`, function timeout 300 s, reserved concurrency 1, log group with 365-day retention.

### IAM
- `OpsimaRemoteAccessRole` no longer holds any Organizations write permission; its trust policy requires
  the Opsima platform role (`aws:PrincipalArn`) in addition to the external ID; `sts:AssumeRole` on the
  dedicated accounts' role is limited to members of the customer's Organization (`aws:ResourceOrgID`).
- The Lambda execution role: `CreateAccount` and `InviteAccountToOrganization` require the `owner=opsima`
  request tag; `TagResource` requires `owner=opsima` and `role=OpsimaOrganizationAccountAccessRole` and no
  other key; `MoveAccount` is limited to accounts tagged `owner=opsima` between the root and the Opsima OU;
  `sts:AssumeRole` on the dedicated accounts' role is limited to members of the Opsima Organization.
- Lambda trust policy conditioned on `aws:SourceAccount` and `aws:SourceArn`.

### SCP
- `iam:GetRole` and `iam:UpdateAssumeRolePolicy` removed: the trust policy of the dedicated accounts' role
  is never modified while an account is a member of the customer's Organization.

### CUR bucket
- Public access block, bucket-owner-enforced ownership, 1130-day expiration, `aws:SourceArn` condition.

### Terraform
- Published as modules with `variables.tf`; the Lambda can be deployed from a locally built package with
  `lambda_filename`, or from the released package pinned with `lambda_source_code_hash`.
