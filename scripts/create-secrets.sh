#!/usr/bin/env bash
# create-secrets.sh
# Creates/updates the per-service AWS Secrets Manager secrets that the app
# reads at runtime. Run manually after `terraform apply` — Terraform never
# creates or stores these values (only the IAM permission to read them, scoped
# to the procurement/<env>/* naming convention this script uses).
#
# Every key here must exactly match what backend/shared/common/src/config/
# secrets.ts's updateConfig() reads — anything else is silently ignored by the app.
#
# Re-running this is safe: existing secrets get a new version (put-secret-value),
# new ones get created. JWT secrets are regenerated each run unless you pass
# -k/--keep-jwt to preserve the current ones (e.g. so existing sessions/refresh
# tokens don't all invalidate at once).
#
# Usage:
#   ./scripts/create-secrets.sh dev
#   ./scripts/create-secrets.sh prod --keep-jwt

set -euo pipefail

ENV=${1:?Usage: $0 <dev|prod> [--keep-jwt]}
KEEP_JWT=false
[ "${2:-}" = "--keep-jwt" ] || [ "${2:-}" = "-k" ] && KEEP_JWT=true

SERVICES=(identity-service finance-service procurement-service document-service ai-service frontend)

echo "==> Selecting Terraform workspace $ENV..."
terraform workspace select "$ENV"

echo "==> Reading Terraform outputs..."
AWS_REGION=$(terraform output -raw aws_region)
S3_BUCKET=$(terraform output -raw s3_bucket_name)
KMS_KEY_ID=$(terraform output -raw kms_key_arn)
APP_HOSTNAME=$(terraform output -raw app_hostname)
BEDROCK_TEXT_MODEL=$(terraform output -raw bedrock_text_model_id)
BEDROCK_EMBEDDING_MODEL=$(terraform output -raw bedrock_embedding_model_id)
COGNITO_USER_POOL_ID=$(terraform output -raw cognito_user_pool_id)
COGNITO_CLIENT_ID=$(terraform output -raw cognito_client_id)
DYNAMODB_TABLES_JSON=$(terraform output -json dynamodb_table_names)
SECRETS_PREFIX=$(terraform output -raw secrets_name_prefix)

# JWT secrets MUST be identical across every service: identity-service signs
# tokens, every other service verifies them. Generating these once here (not
# per-service inside the loop, which was the original bug — each service got
# its own random secret, so cross-service auth could never work) is what
# makes that possible.
if [ "$KEEP_JWT" = true ] && aws secretsmanager describe-secret --secret-id "${SECRETS_PREFIX}/identity-service" --region "$AWS_REGION" >/dev/null 2>&1; then
  EXISTING=$(aws secretsmanager get-secret-value --secret-id "${SECRETS_PREFIX}/identity-service" --region "$AWS_REGION" --query SecretString --output text)
  JWT_SECRET=$(echo "$EXISTING" | jq -r '.JWT_SECRET')
  JWT_REFRESH_SECRET=$(echo "$EXISTING" | jq -r '.JWT_REFRESH_SECRET')
  echo "==> Keeping existing shared JWT secrets"
else
  JWT_SECRET=$(openssl rand -hex 32)
  JWT_REFRESH_SECRET=$(openssl rand -hex 32)
  echo "==> Generated new shared JWT secrets"
fi

for SERVICE in "${SERVICES[@]}"; do
  SECRET_NAME="${SECRETS_PREFIX}/${SERVICE}"

  SECRET_JSON=$(jq -n \
    --arg ENVIRONMENT "$ENV" \
    --arg AWS_REGION "$AWS_REGION" \
    --arg AWS_S3_BUCKET "$S3_BUCKET" \
    --arg AWS_KMS_KEY_ID "$KMS_KEY_ID" \
    --arg JWT_SECRET "$JWT_SECRET" \
    --arg JWT_REFRESH_SECRET "$JWT_REFRESH_SECRET" \
    --arg JWT_EXPIRY "15m" \
    --arg JWT_REFRESH_EXPIRY "7d" \
    --arg CORS_ORIGIN "https://${APP_HOSTNAME}" \
    --arg AWS_BEDROCK_REGION "$AWS_REGION" \
    --arg AWS_BEDROCK_TEXT_MODEL_ID "$BEDROCK_TEXT_MODEL" \
    --arg AWS_BEDROCK_EMBEDDING_MODEL_ID "$BEDROCK_EMBEDDING_MODEL" \
    --arg COGNITO_USER_POOL_ID "$COGNITO_USER_POOL_ID" \
    --arg COGNITO_CLIENT_ID "$COGNITO_CLIENT_ID" \
    --argjson DYNAMODB_TABLES "$DYNAMODB_TABLES_JSON" \
    --arg S3_BUCKET_NAME "$S3_BUCKET" \
    '{
      ENVIRONMENT: $ENVIRONMENT,
      AWS_REGION: $AWS_REGION,
      AWS_S3_BUCKET: $AWS_S3_BUCKET,
      AWS_KMS_KEY_ID: $AWS_KMS_KEY_ID,
      JWT_SECRET: $JWT_SECRET,
      JWT_REFRESH_SECRET: $JWT_REFRESH_SECRET,
      JWT_EXPIRY: $JWT_EXPIRY,
      JWT_REFRESH_EXPIRY: $JWT_REFRESH_EXPIRY,
      CORS_ORIGIN: $CORS_ORIGIN,
      AWS_BEDROCK_REGION: $AWS_BEDROCK_REGION,
      AWS_BEDROCK_TEXT_MODEL_ID: $AWS_BEDROCK_TEXT_MODEL_ID,
      AWS_BEDROCK_EMBEDDING_MODEL_ID: $AWS_BEDROCK_EMBEDDING_MODEL_ID,
      COGNITO_USER_POOL_ID: $COGNITO_USER_POOL_ID,
      COGNITO_CLIENT_ID: $COGNITO_CLIENT_ID,
      DYNAMODB_TABLES: ($DYNAMODB_TABLES | tojson),
      S3_BUCKET_NAME: $S3_BUCKET_NAME
    }')

  if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "==> Updating $SECRET_NAME..."
    aws secretsmanager put-secret-value \
      --secret-id "$SECRET_NAME" \
      --secret-string "$SECRET_JSON" \
      --region "$AWS_REGION" >/dev/null
  else
    echo "==> Creating $SECRET_NAME..."
    aws secretsmanager create-secret \
      --name "$SECRET_NAME" \
      --kms-key-id "$KMS_KEY_ID" \
      --secret-string "$SECRET_JSON" \
      --region "$AWS_REGION" >/dev/null
  fi
done

echo ""
echo "==> Done. Created/updated secrets for: ${SERVICES[*]}"
echo "Prefix: ${SECRETS_PREFIX}/<service>"
