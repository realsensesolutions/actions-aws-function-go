# EventBridge Scheduler IAM role for invoking Lambda
resource "aws_iam_role" "eventbridge_scheduler_role" {
  name = local.eventbridge_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = local.eventbridge_role_name
    Environment = "production"
    CreatedBy   = "alonch/actions-aws-function-go"
    LambdaFor   = var.name
  }
}

# IAM policy to allow EventBridge Scheduler to invoke this specific Lambda function
resource "aws_iam_role_policy" "eventbridge_lambda_invoke" {
  name = "${var.name}-eventbridge-lambda-invoke-${random_id.suffix.hex}"
  role = aws_iam_role.eventbridge_scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.function.arn
      }
    ]
  })
} 