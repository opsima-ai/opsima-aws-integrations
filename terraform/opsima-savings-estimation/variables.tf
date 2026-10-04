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
