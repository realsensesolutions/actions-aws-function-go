# Chrome Lambda Layer integration
# This file contains all Chrome/Chromium-specific configuration

locals {
  # Parse packages YAML
  packages_map = length(var.packages) > 0 ? yamldecode(var.packages) : {}
  
  # Extract Chrome version
  chrome_version = lookup(local.packages_map, "chrome", "")
  chrome_enabled = length(local.chrome_version) > 0
  
  # Chromium-for-lambda download URL pattern
  # ARM64 vs x86_64 based on var.arm
  chrome_arch = var.arm ? "arm64" : "x86_64"
  chrome_os   = "al2023"  # Amazon Linux 2023 matches provided.al2023 runtime
  
  # Construct download URL for chromium-for-lambda
  # Format: https://github.com/chromium-for-lambda/chromium-binaries/releases/download/v{version}/chromium-v{version}-layer-{os}-{arch}.zip
  chrome_download_url = local.chrome_enabled ? (
    "https://github.com/chromium-for-lambda/chromium-binaries/releases/download/v${local.chrome_version}/chromium-v${local.chrome_version}-layer-${local.chrome_os}-${local.chrome_arch}.zip"
  ) : ""
  
  # Chrome environment variables to inject when enabled
  chrome_env_vars = local.chrome_enabled ? {
    CHROMIUM_PATH = "/opt/chromium"
  } : {}
}

# Download chromium layer zip
data "http" "chrome_layer" {
  count = local.chrome_enabled ? 1 : 0
  
  url = local.chrome_download_url
  
  request_headers = {
    Accept = "application/octet-stream"
  }
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

# Write downloaded chromium layer to temporary file
resource "local_file" "chrome_layer" {
  count = local.chrome_enabled ? 1 : 0
  
  filename = "${path.module}/chromium-v${local.chrome_version}-layer-${local.chrome_os}-${local.chrome_arch}.zip"
  content  = data.http.chrome_layer[0].response_body
  
  depends_on = [
    data.http.chrome_layer
  ]
}

# Upload chromium layer zip to S3
resource "aws_s3_object" "chrome_layer" {
  count = local.chrome_enabled ? 1 : 0
  
  bucket = aws_s3_bucket.chrome_layer[0].id
  key    = "chromium-v${local.chrome_version}-layer-${local.chrome_os}-${local.chrome_arch}.zip"
  source = local_file.chrome_layer[0].filename
  
  etag = filemd5(local_file.chrome_layer[0].filename)
  
  tags = {
    Name        = "chromium-v${local.chrome_version}"
    Version     = local.chrome_version
    Architecture = local.chrome_arch
    OS          = local.chrome_os
  }
  
  depends_on = [
    local_file.chrome_layer
  ]
}

# Create Lambda layer from S3
resource "aws_lambda_layer_version" "chrome" {
  count = local.chrome_enabled ? 1 : 0
  
  layer_name          = "${var.name}-chromium-${local.chrome_version}-${local.chrome_arch}"
  s3_bucket           = aws_s3_bucket.chrome_layer[0].id
  s3_key              = aws_s3_object.chrome_layer[0].key
  compatible_runtimes = ["provided.al2023"]
  compatible_architectures = [local.chrome_arch]
  
  depends_on = [
    aws_s3_object.chrome_layer
  ]
}
