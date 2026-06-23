resource "aws_iam_policy" "bedrock_policy" {
  count       = contains(var.services, "ai-service") ? 1 : 0
  name        = "${var.environment}-ai-service-bedrock-policy"
  description = "Bedrock model invoke access for ai-service only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = [
        "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_text_model_id}",
        "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_embedding_model_id}"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bedrock_attach" {
  count      = contains(var.services, "ai-service") ? 1 : 0
  role       = module.irsa["ai-service"].iam_role_name
  policy_arn = aws_iam_policy.bedrock_policy[0].arn
}
