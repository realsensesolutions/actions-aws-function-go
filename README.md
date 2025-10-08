# GitHub Action for AWS Lambda Go Functions

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## Description

This GitHub Action provisions an AWS Lambda function using Go runtime via Terraform. It automatically builds your Go code into a Lambda-compatible binary and deploys it to AWS.

## Inputs

| Name                | Description                                                                            | Required | Default                                      |
| ------------------- | -------------------------------------------------------------------------------------- | -------- | -------------------------------------------- |
| action              | Desired outcome: apply, plan or destroy                                                | false    | apply                                        |
| name                | Function name                                                                          | true     | ""                                           |
| arm                 | Run in ARM compute                                                                     | false    | true                                         |
| worker              | Enable worker mode with SQS queue                                                      | false    | ""                                           |
| entrypoint-file     | Path to main Go file (e.g., main.go or cmd/main.go)                                   | true     | ""                                           |
| working-directory   | Working directory containing go.mod and Go source files (relative to workspace)       | false    | .                                            |
| memory              | 128 (in MB) to 10,240 (in MB)                                                          | false    | 128                                          |
| env                 | List of environment variables in YML format                                            | false    | CREATE\_BY: alonch/actions-aws-function-go |
| permissions         | List of permissions following Github standard of service: read or write. In YML format | false    | ""                                           |
| artifacts           | This folder will be zip and deploy to Lambda                                           | false    | ""                                           |
| timeout             | Maximum time in seconds before aborting the execution                                  | false    | 3                                            |
| allow-public-access | Generate a public URL. WARNING: ANYONE ON THE INTERNET CAN RUN THIS FUNCTION           | false    | ""                                           |
| volume-name         | Name of the EFS volume to create or use. Will be managed by actions-aws-volume        | false    | ""                                           |
| volume-path         | Path where the EFS volume will be mounted in Lambda (defaults to /mnt/{volume-name})  | false    | ""                                           |
| dd-tracing          | Enable Datadog tracing and observability                                               | false    | false                                        |
| dd-api-key          | Datadog API key from GitHub secrets (required if dd-tracing is enabled)                | false    | ""                                           |

## Outputs

| Name       | Description                                         |
| ---------- | --------------------------------------------------- |
| url        | Public accessible URL, if allow-public-access=true  |
| arn        | AWS Lambda ARN                                      |
| queue-arn  | ARN of the SQS queue (if worker mode is enabled)    |
| queue-name | Name of the SQS queue (if worker mode is enabled)   |
| queue-url  | URL of the SQS queue (if worker mode is enabled)    |

## Sample Usage

```yaml
jobs:
  deploy:
    permissions:
      id-token: write
    runs-on: ubuntu-latest
    steps:
      - name: Check out repo
        uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: us-east-1
          role-to-assume: ${{ secrets.ROLE_ARN }}
          role-session-name: ${{ github.actor }}
      - uses: alonch/actions-aws-backend-setup@main
        id: backend
        with:
          instance: demo
      - uses: alonch/actions-aws-function-go@main
        with:
          name: actions-aws-function-go-demo
          working-directory: .
          entrypoint-file: main.go
          allow-public-access: true
```

## Go Lambda Function Requirements

Your Go Lambda function must:

1. **Import the AWS Lambda Go library**:
   ```go
   import "github.com/aws/aws-lambda-go/lambda"
   ```

2. **Have a `go.mod` file** in the same directory as your entrypoint file:
   ```go
   module my-lambda
   
   go 1.22
   
   require (
       github.com/aws/aws-lambda-go v1.48.0
   )
   ```

3. **Use `lambda.Start()` in your main function**:
   ```go
   func main() {
       lambda.Start(handler)
   }
   ```

See the [examples directory](./examples/) for a complete working example.

## Using Persistent Storage with EFS

To create a Lambda function with persistent storage, use the `volume-name` parameter:

```yaml
- uses: alonch/actions-aws-function-go@main
  with:
    name: stateful-lambda-function
    working-directory: .
    entrypoint-file: main.go
    volume-name: db
    timeout: 10 # Note: min 10 seconds when using EFS
```

This will:
1. Create an EFS file system in your default VPC
2. Mount it to your Lambda function at `/mnt/db`
3. All data written to this path will persist across function invocations

**Note:** Using EFS requires the Lambda to run in a VPC, which can increase cold start times. The minimum timeout when using EFS is 10 seconds.

## Worker Mode with SQS Queue

To create a Lambda function with a worker queue, use the `worker` parameter:

```yaml
- uses: alonch/actions-aws-function-go@main
  id: worker
  with:
    name: worker-lambda
    working-directory: .
    entrypoint-file: main.go
    worker: true
```

This will:
1. Create an SQS queue
2. Configure the Lambda function to process messages from the queue
3. Set up appropriate permissions
4. Provide the queue ARN and name as outputs

**Note:** When using worker mode, your Lambda handler function should expect SQS event payloads. See the [examples directory](./examples/) for SQS handling code.

## Network Integration

This action integrates with [actions-aws-network](https://github.com/realsensesolutions/actions-aws-network) to deploy Lambda functions in custom VPC infrastructure with enhanced security.

### Using Custom Network (Recommended)

When you use the network action before this Lambda action, your functions will be deployed in **private subnets** for better security:

```yaml
- uses: realsensesolutions/actions-aws-network@main
  with:
    action: apply
- uses: alonch/actions-aws-function-go@main
  with:
    name: secure-lambda
    working-directory: .
    entrypoint-file: main.go
    volume-name: db  # EFS will be created in private subnets
```

### Network Architecture Benefits

When using the network action, your Lambda gets:
- **Private subnets**: `10.0.32.0/20` and `10.0.48.0/20` across multiple AZs
- **NAT Gateway**: For secure internet access from private subnets
- **Pre-configured security groups**: Optimized for private network access
- **Multi-AZ deployment**: High availability and fault tolerance

### Fallback Behavior

If the network action is not used, Lambda functions with EFS will deploy in the **default VPC** with default subnets. This maintains backward compatibility with existing workflows.

## Service Permissions

You can specify AWS service permissions using the `permissions` parameter:

```yaml
- uses: alonch/actions-aws-function-go@main
  with:
    name: lambda-with-permissions
    working-directory: .
    entrypoint-file: main.go
    permissions: |
      s3: read
      dynamodb: write
      sqs: write
```

Supported services and access levels:
- `s3`: `read` or `write`
- `dynamodb`: `read` or `write`
- `sqs`: `read` or `write`
- `ses`: `read` or `write`
- `sns`: `read` or `write`
- `kinesis`: `read` or `write`
- `rds`: `read` or `write`
- `cloudwatch`: `read` or `write`
- `stepfunctions`: `read` or `write`
- `secretsmanager`: `read` or `write`
- `ssm`: `read` or `write`
- `eventbridge`: `read` or `write`
- `ecr`: `read` or `write`
- `redshift`: `read` or `write`
- `glue`: `read` or `write`
- `athena`: `read` or `write`
- `cognito`: `read` or `write` (write includes `AdminUpdateUserAttributes`)
- `apigateway`: `read` or `write`
- `lambda`: `read` or `write`
- `iot`: `read` or `write`
- `xray`: `read` or `write`

This uses standard AWS managed policies for each service and access level.

## Datadog Integration

This action provides built-in support for Datadog observability, allowing you to monitor your Lambda functions with distributed tracing, metrics, and logs.

### Quick Start

To enable Datadog monitoring for your Lambda function:

```yaml
- uses: alonch/actions-aws-function-go@main
  with:
    name: my-lambda-function
    working-directory: .
    entrypoint-file: main.go
    dd-tracing: true
    dd-api-key: ${{ secrets.DATADOG_API_KEY }}
```

### What Gets Configured

When `dd-tracing: true` is set, the action automatically:

1. **Creates an AWS Secrets Manager secret** named `datadog-api-key` (shared across all your Lambda functions)
2. **Attaches the Datadog Lambda Extension layer** (v86) to your function
3. **Injects environment variables**:
   - `DD_SITE`: `datadoghq.com` (US1 region)
   - `DD_API_KEY_SECRET_ARN`: ARN of the created secret
4. **Grants IAM permissions** for Secrets Manager access

### Custom Configuration

You can customize Datadog settings using the `env` input:

```yaml
- uses: alonch/actions-aws-function-go@main
  with:
    name: my-lambda-function
    working-directory: .
    entrypoint-file: main.go
    dd-tracing: true
    dd-api-key: ${{ secrets.DATADOG_API_KEY }}
    env: |
      DD_SERVICE: my-custom-service
      DD_ENV: production
      DD_VERSION: ${{ github.sha }}
      DD_SITE: datadoghq.eu
      DD_LOGS_INJECTION: true
      DD_TRACE_ENABLED: true
```

### Required Code Changes

To enable distributed tracing, you must wrap your Lambda handler with the Datadog wrapper:

**1. Add the Datadog dependency to your `go.mod`:**

```go
require (
    github.com/DataDog/datadog-lambda-go v1.13.0
    github.com/aws/aws-lambda-go v1.48.0
)
```

**2. Update your main function:**

```go
package main

import (
    "context"
    ddlambda "github.com/DataDog/datadog-lambda-go"
    "github.com/aws/aws-lambda-go/lambda"
)

func handler(ctx context.Context, event interface{}) (interface{}, error) {
    // Your handler logic
    return "ok", nil
}

func main() {
    // Wrap your handler with Datadog
    lambda.Start(ddlambda.WrapFunction(handler, nil))
}
```

**Optional: Conditional wrapping** (works with or without Datadog):

```go
import "os"

func main() {
    if os.Getenv("DD_API_KEY_SECRET_ARN") != "" {
        // Datadog enabled
        lambda.Start(ddlambda.WrapFunction(handler, nil))
    } else {
        // Standard Lambda handler
        lambda.Start(handler)
    }
}
```

### Architecture Support

The action automatically selects the correct Datadog Extension layer based on your `arm` setting:
- **ARM64**: Uses `Datadog-Extension-ARM` layer
- **x86_64**: Uses `Datadog-Extension` layer (when `arm: false`)

### Prerequisites

1. **Create a Datadog account** at [datadoghq.com](https://www.datadoghq.com/)
2. **Generate a Datadog API key** from your Datadog dashboard
3. **Add the API key as a GitHub secret** named `DATADOG_API_KEY`

### What You Get

With Datadog enabled, you can monitor:
- **Distributed traces** across your Lambda functions and services
- **Custom metrics** using `ddlambda.Metric()`
- **Enhanced logs** with automatic trace correlation
- **Cold start metrics** and invocation details
- **Performance insights** and bottleneck detection

### Example with Custom Metrics

```go
import ddlambda "github.com/DataDog/datadog-lambda-go"

func handler(ctx context.Context, event interface{}) (interface{}, error) {
    // Submit a custom metric
    ddlambda.Metric(
        "my_app.orders.count",
        42,
        "environment:prod", "team:backend",
    )
    
    return "ok", nil
}
```

### Notes

- The Datadog secret persists even when Lambda functions are destroyed (cost: ~$0.40/month)
- The Datadog Extension layer version (v86) is hardcoded and may need updates
- For non-US1 Datadog sites, override `DD_SITE` using the `env` input
- Basic metrics are collected even without wrapping your handler (via the Extension layer)
- Distributed tracing requires handler wrapping

### Troubleshooting

**Datadog not receiving data:**
- Verify `DATADOG_API_KEY` GitHub secret is set correctly
- Check CloudWatch Logs for Datadog Extension errors
- Ensure your Lambda has internet access (NAT Gateway for VPC functions)

**Import errors:**
- Run `go mod tidy` in your working directory
- Verify `github.com/DataDog/datadog-lambda-go` is in your `go.mod`

See the [examples directory](./examples/main.go) for a complete working example with Datadog integration.