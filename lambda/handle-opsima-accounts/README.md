# HandleOpsimaAccounts Lambda function

Deployed in the customer's Management Account by the `opsima-remote-access` Terraform module or the
`opsima-cloud_formation-full_access_lambda.yaml` stack. Opsima invokes it through `OpsimaRemoteAccessRole`;
the function is the only component holding account-creation rights, and its execution role is limited to the
actions declared in the Terraform module and the CloudFormation template.

## Actions

| Action | What it does |
|---|---|
| `CREATE` | Creates a dedicated account (`ocm+…`) tagged `owner=opsima`, waits for its creation, moves it into the Opsima OU. |
| `INVITE` | Transfers an account from the Opsima Organization: assumes the account's Opsima role under a restrictive session policy, verifies the account is a member of the Opsima Organization, invites it, accepts the invitation on its behalf, moves it into the Opsima OU. |
| `HEALTHCHECK` | Returns `ok` and the version of the deployed function, so that Opsima knows which release runs in your account. |

## Logs

The function writes two structured records per invocation: `ACTION_STARTED`, with the action and the
account it applies to, then `ACTION_SUCCEEDED` or `ACTION_FAILED`, with the response returned to Opsima.
A failed action carries the step that failed (`details.step`), the identifiers known at that point and
the name and message of the original error. Records are emitted in JSON (log format set by the template),
so they can be filtered in CloudWatch Logs, for example `{ $.message.event = "ACTION_FAILED" }`.

The raw input payload and the session credentials are never logged.

## Environment variables

All of them are set by the Terraform module or the CloudFormation stack.

| Variable | Meaning |
|---|---|
| `OPSIMA_OU_ID` | Organizational Unit of the customer's Organization that receives Opsima accounts |
| `ORGANIZATION_ID` | ID of the customer's Organization |
| `ORGANIZATION_ROOT_ID` | Root ID of the customer's Organization |
| `OPSIMA_ORGANIZATION_ID` | ID of the Opsima Organization: transferred accounts must come from it |
| `OPSIMA_MANAGEMENT_ACCOUNT_ID` | Management Account of the Opsima Organization |

## Build

Requires Node.js 24 (the Lambda runtime) and `zip`.

```bash
npm ci
npm run typecheck
npm run package      # builds dist/handle-opsima-accounts.zip and prints its SHA-256
```

The package contains a single compiled file; the AWS SDK is provided by the Lambda runtime. The build is
reproducible: the same tag produces the same zip and the same hash on any machine, so you can compare your
build with the hash published in the release notes.
