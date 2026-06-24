output "sender_identity_arn" {
  value = aws_ses_email_identity.sender.arn
}

output "recipient_identity_arn" {
  value = aws_ses_email_identity.recipient.arn
}
