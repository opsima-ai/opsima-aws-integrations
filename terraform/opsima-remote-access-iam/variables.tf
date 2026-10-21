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

# Provided by Opsima for your organization

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

variable "opsima_invoice_unit_arn" {
  description = "ARN of an existing Invoice Unit of your Organization dedicated to Opsima accounts. Provided by you; leave empty to let Opsima create it at onboarding."
  type        = string
  default     = ""

  validation {
    condition     = var.opsima_invoice_unit_arn == "" || can(regex("^arn:aws:invoicing::[0-9]{12}:invoice-unit/[A-Za-z0-9-]+$", var.opsima_invoice_unit_arn))
    error_message = "opsima_invoice_unit_arn must be empty or look like arn:aws:invoicing::123456789012:invoice-unit/xxxxxxxx."
  }
}

variable "allow_account_quota_increase" {
  description = "Grants the Opsima role the right to request an increase of the account quota of your Organization (servicequotas:RequestServiceQuotaIncrease on quota L-E619E033). Set it to false to keep quota increases on your side."
  type        = bool
  default     = true
}
