resource "aws_cognito_user_pool" "pool" {
  name = "${var.environment}-procurement-pool"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  tags = var.tags
}

resource "aws_cognito_user_pool_client" "client" {
  name                = "${var.environment}-procurement-client"
  user_pool_id        = aws_cognito_user_pool.pool.id
  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
}
