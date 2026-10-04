# Permissions

Opsima works on a least-privilege basis: each role is granted only the permissions required for its task.
This page lists every permission in the default deployment (`opsima-remote-access`) and why it exists.
The IAM-only and savings-estimation variants are subsets, noted at the end.

## OpsimaRemoteAccessRole (your Management Account)

Assumed by Opsima's platform role only, with your external ID (`sts:ExternalId` and `aws:PrincipalArn`
conditions on the trust policy).

| Permission | Why |
|---|---|
| `bcm-data-exports:CreateExport`, `TagResource`, `ListExports`, `GetExport`, `cur:PutReportDefinition`, `DescribeReportDefinitions`, `TagResource` | Set up and read the Cost and Usage Report that Opsima analyses. The `cur:*` actions are called by Data Exports under the hood. |
| `ce:GetCostAndUsage`, `GetDimensionValues`, `GetSavingsPlansCoverage`, `GetSavingsPlansUtilization`, `GetReservationCoverage`, `GetReservationUtilization` | Read Cost Explorer, which only sees the whole Organization from the Management Account. |
| `s3:GetBucketLocation`, `GetObject`, `GetObjectVersion`, `ListBucket` on the CUR bucket | Read the report files. |
| `organizations:ListAccounts`, `ListTagsForResource` | List the accounts of the Organization and identify Opsima accounts by their tags. |
| `invoicing:CreateInvoiceUnit`, `GetInvoiceUnit`, `UpdateInvoiceUnit`, `TagResource` | Place every dedicated account in a single Invoice Unit so that Opsima commitment charges appear on a separate invoice. You can provide the Invoice Unit at onboarding; otherwise Opsima creates it. |
| `lambda:InvokeFunction` on `HandleOpsimaAccounts` | Trigger account creation and transfers. |
| `sts:AssumeRole` on `OpsimaOrganizationAccountAccessRole`, only in members of your Organization (`aws:ResourceOrgID`) | Operate inside the dedicated accounts: buy and tag commitments, set contact details. |
| `servicequotas:RequestServiceQuotaIncrease` on the Organization account limit (`L-E619E033`) | Request an increase of the number of accounts when the limit is reached, so that account creations and transfers are not delayed. Can be removed if you prefer to raise the quota yourself. |

This role holds no Organizations write permission.

## HandleOpsimaAccounts execution role (your Management Account)

| Permission | Why |
|---|---|
| `logs:CreateLogStream`, `PutLogEvents` on its own log group | Write its logs. The log group is created by the template with a 365-day retention. |
| `organizations:DescribeCreateAccountStatus` | Wait for an account creation to complete. |
| `organizations:CreateAccount`, `InviteAccountToOrganization`, only with the request tag `owner=opsima` | Create a dedicated account, or invite one transferred from the Opsima Organization. |
| `organizations:TagResource`, only with `owner=opsima` and `role=OpsimaOrganizationAccountAccessRole` and no other key | Required by AWS to apply the tags passed to `CreateAccount` and `InviteAccountToOrganization`. The function never calls it directly. |
| `organizations:MoveAccount` on accounts tagged `owner=opsima`, with your root and the Opsima OU as the only allowed parents | Move a new or transferred account into the Opsima OU. |
| `sts:AssumeRole` on `OpsimaOrganizationAccountAccessRole`, only in members of the Opsima Organization (`aws:ResourceOrgID`) | Accept your invitation on behalf of a transferred account, under a session policy limited to `organizations:DescribeOrganization` and `organizations:AcceptHandshake`. |

The target OU and root are set by environment variables from your template, not by the invocation payload.

## OpsimaOrganizationAccountAccessRole (each dedicated account)

Created by `CreateAccount` with `AdministratorAccess`, trusting your Management Account. What it can
actually do is bounded by the SCP you attach to the Opsima OU: Savings Plans and Reserved Instances
operations, account contact information, the ElastiCache service-linked role, and accepting an invitation
when an account is transferred out. See [security-controls.md](security-controls.md).

## Variants

- **IAM only** (`opsima-remote-access-iam`): no Lambda function; `OpsimaRemoteAccessRole` holds
  `CreateAccount`, `InviteAccountToOrganization` and `MoveAccount` with the same conditions as above.
- **Savings estimation** (`opsima-savings-estimation`): `OpsimaLimitedAccessRole` with the Cost Explorer
  read permissions only.
