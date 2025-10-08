# Datadog Lambda Extension integration
# This file contains all Datadog-specific configuration

locals {
  # Datadog Extension Layer version (hardcoded)
  dd_extension_version = "86"

  # Datadog Extension Layer ARN - architecture-aware
  # Format: arn:aws:lambda:<region>:464622532012:layer:Datadog-Extension(-ARM):<version>
  dd_layer_arn = var.dd_enabled ? (
    var.arm ?
    "arn:aws:lambda:${data.aws_region.current.name}:464622532012:layer:Datadog-Extension-ARM:${local.dd_extension_version}" :
    "arn:aws:lambda:${data.aws_region.current.name}:464622532012:layer:Datadog-Extension:${local.dd_extension_version}"
  ) : ""

  # Datadog environment variables to inject when enabled
  dd_env_vars = var.dd_enabled ? {
    DD_SITE                = "datadoghq.com"
    DD_API_KEY_SECRET_ARN = var.dd_secret_arn
  } : {}

  # IAM policy for Secrets Manager access (when Datadog is enabled)
  dd_secrets_policy = var.dd_enabled && length(var.dd_secret_arn) > 0 ? {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.dd_secret_arn
      }
    ]
  } : null
}

