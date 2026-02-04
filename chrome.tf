# Chrome Lambda Layer integration
# This file contains all Chrome/Chromium-specific configuration

locals {
  # Parse packages YAML
  packages_map = length(var.packages) > 0 ? yamldecode(var.packages) : {}
  
  # Extract Chrome version (convert to string since YAML may parse it as number)
  chrome_version_raw = try(local.packages_map["chrome"], null)
  chrome_version     = local.chrome_version_raw != null ? tostring(local.chrome_version_raw) : ""
  chrome_enabled     = length(local.chrome_version) > 0 && length(var.chrome_layer_path) > 0
  
  # ARM64 vs x64 based on var.arm (matching Sparticuz/chromium naming)
  chrome_arch = var.arm ? "arm64" : "x64"
  
  # For Lambda compatible_architectures, we need the AWS naming
  chrome_arch_aws = var.arm ? "arm64" : "x86_64"
  
  # Chrome environment variables to inject when enabled
  chrome_env_vars = local.chrome_enabled ? {
    CHROMIUM_PATH = "/opt/chromium"
  } : {}
}

# S3 bucket for storing Lambda layers
resource "aws_s3_bucket" "chrome_layer" {
  count = local.chrome_enabled ? 1 : 0
  
  bucket = "${var.name}-lambda-layers-${random_id.suffix.hex}"
  
  tags = {
    Name        = "${var.name}-lambda-layers"
    ManagedBy   = "actions-aws-function-go"
    Purpose     = "lambda-layers"
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "chrome_layer" {
  count = local.chrome_enabled ? 1 : 0
  
  bucket = aws_s3_bucket.chrome_layer[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Upload chromium layer zip to S3 from local file (downloaded by GitHub Action)
resource "aws_s3_object" "chrome_layer" {
  count = local.chrome_enabled ? 1 : 0
  
  bucket = aws_s3_bucket.chrome_layer[0].id
  key    = "chromium-v${local.chrome_version}-layer-${local.chrome_os}-${local.chrome_arch}.zip"
  source = var.chrome_layer_path
  etag   = filemd5(var.chrome_layer_path)
  
  tags = {
    Name         = "chromium-v${local.chrome_version}"
    Version      = local.chrome_version
    Architecture = local.chrome_arch
    OS           = local.chrome_os
  }
}

# Create Lambda layer from S3
resource "aws_lambda_layer_version" "chrome" {
  count = local.chrome_enabled ? 1 : 0
  
  layer_name               = "${var.name}-chromium-${local.chrome_version}-${local.chrome_arch}"
  s3_bucket                = aws_s3_bucket.chrome_layer[0].id
  s3_key                   = aws_s3_object.chrome_layer[0].key
  compatible_runtimes      = ["provided.al2023"]
  compatible_architectures = [local.chrome_arch_aws]
  
  depends_on = [
    aws_s3_object.chrome_layer
  ]
}
