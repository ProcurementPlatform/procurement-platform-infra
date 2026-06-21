# Monitoring alerts parsing Lambda (terraform-aws-modules/lambda/aws)
# Triggered by SNS, renders a templated HTML email, sends it via SES.
module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name = "procurement-${var.environment}-monitoring-alerts"
  description   = "Processes CloudWatch and ASG EventBridge alerts and sends HTML emails via SES"
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 30

  source_path = "${path.module}/lambda"

  tracing_mode = "Active"

  environment_variables = {
    SENDER_EMAIL    = var.sender_email
    RECIPIENT_EMAIL = var.recipient_email
    ENVIRONMENT     = var.environment
  }

  attach_policy_statements = true
  policy_statements = {
    ses = {
      effect    = "Allow"
      actions   = ["ses:SendEmail", "ses:SendRawEmail"]
      resources = [var.ses_sender_identity_arn]
    }
  }

  allowed_triggers = {
    SNS = {
      principal  = "sns.amazonaws.com"
      source_arn = var.sns_topic_arn
    }
  }

  create_current_version_allowed_triggers = false

  tags = var.tags
}
