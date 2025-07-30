locals {
  function_name       = "${var.name}-${random_id.suffix.hex}"
  lambda_handler      = "bootstrap"       # Go Lambda handler is always bootstrap
  runtime             = "provided.al2023" # Go uses provided runtime
  lambda_architecture = var.arm ? ["arm64"] : ["x86_64"]

  # EFS configuration
  create_efs = length(var.volume) > 0
  mount_path = length(var.volume_path) > 0 ? var.volume_path : "/mnt/${var.volume}"

  # Network configuration - use provided network or fall back to default
  use_custom_network = length(var.vpc_id) > 0 && (length(var.subnet_public_ids) > 0 || length(var.subnet_private_ids) > 0)
  vpc_id             = local.use_custom_network ? var.vpc_id : (local.create_efs ? data.aws_vpc.default[0].id : "")

  # Use subnet preference based on use_public_subnet variable
  subnet_ids = local.use_custom_network ? (
    var.use_public_subnet ? (
      length(var.subnet_public_ids) > 0 ? split(",", var.subnet_public_ids) : split(",", var.subnet_private_ids)
    ) : (
      length(var.subnet_private_ids) > 0 ? split(",", var.subnet_private_ids) : split(",", var.subnet_public_ids)
    )
  ) : (local.create_efs ? data.aws_subnets.default[0].ids : [])

  # Debug output - will show in Terraform logs
  debug_arn_received = "EFS Access Point ARN received: ${var.efs_access_point_arn}"

  # Fix ARN format that's missing region and account
  # Example of malformed: arn:aws:elasticfilesystem::12345:access-point/fsap-123
  # Example of correct: arn:aws:elasticfilesystem:us-west-2:12345:access-point/fsap-123
  formatted_arn = length(var.efs_access_point_arn) > 0 ? (
    # Check common malformation pattern with :: (missing region)
    can(regex("arn:aws:elasticfilesystem::\\d+:access-point/fsap-[a-f0-9]+", var.efs_access_point_arn)) ?
    replace(var.efs_access_point_arn, "arn:aws:elasticfilesystem::", "arn:aws:elasticfilesystem:${data.aws_region.current.name}:") :
    var.efs_access_point_arn
  ) : ""

  # Debug output - will show in Terraform logs
  debug_arn_formatted = "EFS Access Point ARN formatted: ${local.formatted_arn}"

  # EventBridge Scheduler role name and ARN (deterministic)
  eventbridge_role_name = substr("${var.name}-eventbridge-scheduler-role-${random_id.suffix.hex}", 0, 64)
  eventbridge_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.eventbridge_role_name}"

  # Parse environment variables from YAML
  env_vars_base = length(var.env) > 0 ? yamldecode(var.env) : {}
  
  # Add EventBridge Scheduler role ARN to environment variables
  env_vars = merge(local.env_vars_base, {
    EVENTBRIDGE_SCHEDULER_ROLE_ARN = local.eventbridge_role_arn
  })

  # Parse permissions from YAML
  permissions_map = length(var.permissions) > 0 ? yamldecode(var.permissions) : {}

  # Services and their corresponding policies
  services = {
    s3 = {
      read  = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
    }
    dynamodb = {
      read  = ["arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"]
    }
    sqs = {
      read  = ["arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonSQSFullAccess"]
    }
    ses = {
      read  = ["arn:aws:iam::aws:policy/AmazonSESReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonSESFullAccess"]
    }
    sns = {
      read  = ["arn:aws:iam::aws:policy/AmazonSNSReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonSNSFullAccess"]
    }
    kinesis = {
      read  = ["arn:aws:iam::aws:policy/AmazonKinesisReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonKinesisFullAccess"]
    }
    rds = {
      read  = ["arn:aws:iam::aws:policy/AmazonRDSReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonRDSFullAccess"]
    }
    cloudwatch = {
      read  = ["arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/CloudWatchFullAccess"]
    }
    stepfunctions = {
      read  = ["arn:aws:iam::aws:policy/AWSStepFunctionsReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"]
    }
    secretsmanager = {
      read  = ["arn:aws:iam::aws:policy/SecretsManagerReadWrite"]
      write = ["arn:aws:iam::aws:policy/SecretsManagerReadWrite"]
    }
    ssm = {
      read  = ["arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonSSMFullAccess"]
    }
    eventbridge = {
      read  = ["arn:aws:iam::aws:policy/AmazonEventBridgeReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"]
    }
    ecr = {
      read  = ["arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"]
      write = ["arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"]
    }
    redshift = {
      read  = ["arn:aws:iam::aws:policy/AmazonRedshiftReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonRedshiftFullAccess"]
    }
    glue = {
      read  = ["arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"]
      write = ["arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"]
    }
    athena = {
      read  = ["arn:aws:iam::aws:policy/AmazonAthenaFullAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonAthenaFullAccess"]
    }
    cognito = {
      read  = ["arn:aws:iam::aws:policy/AmazonCognitoReadOnly"]
      write = ["arn:aws:iam::aws:policy/AmazonCognitoPowerUser"]
    }
    apigateway = {
      read  = ["arn:aws:iam::aws:policy/AmazonAPIGatewayInvokeFullAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator"]
    }
    lambda = {
      read  = ["arn:aws:iam::aws:policy/AWSLambdaReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AWSLambdaFullAccess"]
    }
    iot = {
      read  = ["arn:aws:iam::aws:policy/AWSIoTDataAccess"]
      write = ["arn:aws:iam::aws:policy/AWSIoTFullAccess"]
    }
    xray = {
      read  = ["arn:aws:iam::aws:policy/AWSXRayReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AWSXRayFullAccess"]
    }
  }

  # Base policies to always include - removed from dynamic attachment
  # base_policies = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]

  # SQS policy for worker mode
  worker_policies = var.worker == "true" ? ["arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"] : []

  # Process permissions to get list of policy ARNs
  service_policies = length(var.permissions) > 0 ? flatten([
    for service, access_level in local.permissions_map :
    lookup(local.services, service, null) != null ?
    lookup(lookup(local.services, service, {}), access_level, []) : []
  ]) : []

  # Combine all policies EXCEPT the basic execution role
  policy_arns = distinct(concat(local.worker_policies, local.service_policies))

  # Determine if we should create a function URL
  create_function_url = length(var.allow_public_access) > 0
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Note: The lambda_function.zip is created by the GitHub Action build step
# No archive_file data source needed since we build the Go binary externally

# Create the IAM role for the Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.name}-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Keep the basic Lambda execution policy as a separate attachment
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Dynamic policy attachments for additional policies
resource "aws_iam_role_policy_attachment" "lambda_policies" {
  for_each = { for arn in local.policy_arns : replace(basename(arn), ":", "_") => arn }

  role       = aws_iam_role.lambda_role.name
  policy_arn = each.value
}

# Create the Lambda function
resource "aws_lambda_function" "function" {
  function_name    = local.function_name
  filename         = "${path.module}/lambda_function.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_function.zip")
  role             = aws_iam_role.lambda_role.arn
  handler          = local.lambda_handler
  runtime          = local.runtime
  memory_size      = var.memory
  timeout          = var.timeout
  architectures    = local.lambda_architecture
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_policies,
    aws_iam_role_policy_attachment.lambda_vpc_access
  ]

  environment {
    variables = local.env_vars
  }

  # VPC configuration for EFS
  dynamic "vpc_config" {
    for_each = local.create_efs ? [1] : []
    content {
      subnet_ids                  = local.subnet_ids
      security_group_ids          = [aws_security_group.lambda[0].id]
      ipv6_allowed_for_dual_stack = true
    }
  }

  # EFS configuration
  dynamic "file_system_config" {
    for_each = local.create_efs && length(local.formatted_arn) > 0 ? [1] : []
    content {
      # arn is provided directly from GitHub Action output via TF_VAR
      arn              = local.formatted_arn
      local_mount_path = local.mount_path
    }
  }

  # Increase timeout for functions with EFS to at least 10 seconds
  # as Lambda cold starts with EFS can take longer
  lifecycle {
    precondition {
      condition     = !local.create_efs || var.timeout >= 10
      error_message = "When using EFS volumes, timeout must be at least 10 seconds to accommodate for potential cold starts."
    }
  }
}

# Create function URL if public access is allowed
resource "aws_lambda_function_url" "function_url" {
  count              = local.create_function_url ? 1 : 0
  function_name      = aws_lambda_function.function.function_name
  authorization_type = "NONE"

  # cors {
  #  allow_origins = ["*"]
  #  allow_methods = ["GET", "POST"]
  #  allow_headers = ["*"]
  #  max_age       = 86400
  #}
}

# VPC and subnet data sources for fallback to default VPC
data "aws_vpc" "default" {
  count   = local.create_efs && !local.use_custom_network ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = local.create_efs && !local.use_custom_network ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Get current region and account info
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}