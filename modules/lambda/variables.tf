variable "environment" { type = string }
variable "sender_email" { type = string }
variable "recipient_email" { type = string }
variable "sns_topic_arn" { type = string }
variable "ses_sender_identity_arn" { type = string }
variable "ses_recipient_identity_arn" { type = string }
variable "tags" { type = map(string) }
