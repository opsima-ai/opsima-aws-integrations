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

# Your existing Cost and Usage Report (Data Exports)

variable "cur_export_name" {
  description = "Name of the existing Cost and Usage Report export (Billing and Cost Management > Data Exports) Opsima may read."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z!\\-_.*'()]{1,128}$", var.cur_export_name))
    error_message = "cur_export_name must match the Data Exports naming rules: 1 to 128 characters among letters, digits and !-_.*'()."
  }
}

variable "cur_bucket_name" {
  description = "Name of the S3 bucket receiving the export."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.cur_bucket_name))
    error_message = "cur_bucket_name must be a valid S3 bucket name."
  }
}

variable "cur_bucket_prefix" {
  description = "S3 prefix of the export inside the bucket, without leading or trailing slash. Empty grants read access to the whole bucket."
  type        = string
  default     = ""

  validation {
    condition     = !startswith(var.cur_bucket_prefix, "/") && !endswith(var.cur_bucket_prefix, "/")
    error_message = "cur_bucket_prefix must not start or end with a slash."
  }
}
