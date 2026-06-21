variable "environment" { type = string }

variable "tables" {
  description = "Map of table name to its list of GSIs (every GSI here is a single-attribute, String, hash-key-only index — matches every index in the app today)."
  type = map(list(object({
    index_name     = string
    attribute_name = string
  })))
}

variable "kms_key_arn" { type = string }
variable "tags" { type = map(string) }
