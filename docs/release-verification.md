# Verifying and pinning a release

Every release is a Git tag and a GitHub Release carrying `handle-opsima-accounts-<version>.zip` and a
`SHA256SUMS` file. The same zip is published to `s3://opsima-public-prod/lambda/handle-opsima-accounts-<version>.zip`,
a key that is never overwritten.

## Verify the released package

```bash
VERSION=11.0.0
aws s3 cp "s3://opsima-public-prod/lambda/handle-opsima-accounts-${VERSION}.zip" .
shasum -a 256 "handle-opsima-accounts-${VERSION}.zip"      # compare with SHA256SUMS of the release
```

## Build it yourself

The build is reproducible: the same tag gives the same zip and the same hash.

```bash
git clone --branch "v${VERSION}" https://github.com/opsima-ai/opsima-aws-integrations.git
cd opsima-aws-integrations/lambda/handle-opsima-accounts
npm run package        # prints the SHA-256 of dist/handle-opsima-accounts.zip
```

## Pin the package in Terraform

Deploy your own build:

```hcl
module "opsima" {
  source          = "git::https://github.com/opsima-ai/opsima-aws-integrations.git//terraform/opsima-remote-access?ref=v11.0.0"
  lambda_filename = "${path.module}/handle-opsima-accounts.zip"
  # ...
}
```

Or deploy the released package, pinned by its hash (base64 of the SHA-256, as printed by `npm run package`):

```hcl
module "opsima" {
  source                  = "git::https://github.com/opsima-ai/opsima-aws-integrations.git//terraform/opsima-remote-access?ref=v11.0.0"
  lambda_s3_key           = "lambda/handle-opsima-accounts-11.0.0.zip"
  lambda_source_code_hash = "<base64 sha256>"
  # ...
}
```

In both cases Terraform refuses to deploy a package whose hash differs from the one declared, and any
change appears in the plan. Nothing changes in your account until you update the pin and apply.

CloudFormation has no hash check for packages loaded from S3: pin the versioned key, which is immutable.
