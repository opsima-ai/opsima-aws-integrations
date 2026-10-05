# Provided by Opsima: fixed identifiers, the defaults are the only valid values

variable "opsima_principal" {
  description = "Opsima AWS account allowed to assume the Opsima role. Provided by Opsima: the default is the only valid value."
  type        = string
  default     = "539247457822"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.opsima_principal))
    error_message = "opsima_principal must be a 12-digit AWS account ID."
  }
}

variable "opsima_organization_id" {
  description = "ID of the Opsima AWS Organization, which transferred accounts always come from. Provided by Opsima: the default is the only valid value."
  type        = string
  default     = "o-6wvylp8huu"

  validation {
    condition     = can(regex("^o-[a-z0-9]{10}$", var.opsima_organization_id))
    error_message = "opsima_organization_id must look like o-xxxxxxxxxx."
  }
}

variable "opsima_management_account_id" {
  description = "Management Account of the Opsima AWS Organization. Provided by Opsima: the default is the only valid value."
  type        = string
  default     = "730335300397"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.opsima_management_account_id))
    error_message = "opsima_management_account_id must be a 12-digit AWS account ID."
  }
}

# Provided by Opsima for your Organization

variable "external_id" {
  description = "External ID securing the trust policy of the Opsima role. Provided by Opsima."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.external_id))
    error_message = "external_id must be a UUID."
  }
}

variable "customer_short_id" {
  description = "Short ID identifying your organization at Opsima, used to name the CUR bucket and the Opsima OU. Provided by Opsima."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{10}$", var.customer_short_id))
    error_message = "customer_short_id must be 10 hexadecimal characters."
  }
}

# Provided by you, from your Organization

variable "organization_id" {
  description = "ID of your AWS Organization (o-xxxxxxxxxx). Provided by you, from your Organization."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10}$", var.organization_id))
    error_message = "organization_id must look like o-xxxxxxxxxx."
  }
}

variable "organization_root_id" {
  description = "ID of the root of your AWS Organization (r-xxxx). Provided by you, from your Organization."
  type        = string

  validation {
    condition     = can(regex("^r-[a-z0-9]{4,32}$", var.organization_root_id))
    error_message = "organization_root_id must look like r-xxxx."
  }
}

variable "opsima_organizational_unit_id" {
  description = "ID of an existing Organizational Unit of your Organization to host Opsima accounts. Provided by you, together with create_opsima_organizational_unit = false; leave empty to let the module create one."
  type        = string
  default     = ""

  validation {
    condition     = var.opsima_organizational_unit_id == "" || can(regex("^ou-[a-z0-9]{4,32}-[a-z0-9]{8,32}$", var.opsima_organizational_unit_id))
    error_message = "opsima_organizational_unit_id must be empty or look like ou-xxxx-xxxxxxxx."
  }
}

variable "create_opsima_organizational_unit" {
  description = "Whether the module creates the Organizational Unit hosting Opsima accounts. Set it to false when you provide opsima_organizational_unit_id."
  type        = bool
  default     = true
}

variable "create_cur_bucket" {
  description = "Whether to create the S3 bucket receiving the Cost and Usage Report."
  type        = bool
  default     = true
}

# Lambda package

variable "lambda_filename" {
  description = "Path to handle-opsima-accounts.zip, built from the release tag or downloaded from the GitHub Release. Provided by you."
  type        = string
}
