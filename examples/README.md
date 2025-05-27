# Go Lambda Function Examples

This directory contains example Go Lambda functions that demonstrate how to use the `actions-aws-function-go` GitHub Action.

## Files

- `main.go` - A comprehensive Lambda function that handles multiple event types
- `go.mod` - Go module definition with required dependencies

## Features Demonstrated

### 1. API Gateway Integration
The function can handle API Gateway proxy requests and return proper HTTP responses with CORS headers.

**Example Request:**
```json
{
  "name": "World",
  "message": "Hello from the client!"
}
```

**Example Response:**
```json
{
  "message": "Hello from AWS Lambda with Go!",
  "method": "POST",
  "path": "/hello",
  "greeting": "Hello, World!",
  "echo": "Hello from the client!"
}
```

### 2. SQS Worker Mode
When deployed with `worker: true`, the function can process SQS messages automatically.

### 3. Generic Event Handling
The function includes a router that automatically detects the event type and routes to the appropriate handler.

## Usage in GitHub Actions

```yaml
- name: Deploy Lambda Function
  uses: your-org/actions-aws-function-go@main
  with:
    name: my-go-function
    entrypoint-file: examples/main.go
    memory: 256
    timeout: 15
    allow-public-access: true
    permissions: |
      s3: read
      dynamodb: write
```

## Local Development

To test the function locally:

1. Install dependencies:
   ```bash
   cd examples
   go mod tidy
   ```

2. Build the function:
   ```bash
   GOOS=linux GOARCH=amd64 go build -o bootstrap main.go
   ```

3. Test with AWS SAM Local (optional):
   ```bash
   sam local start-api
   ```

## Dependencies

The function uses the official AWS Lambda Go library:
- `github.com/aws/aws-lambda-go` - AWS Lambda runtime for Go

## Event Types Supported

- **API Gateway Proxy Events** - For HTTP/REST APIs
- **SQS Events** - For message queue processing
- **Generic Events** - Fallback for any other event type

The function automatically detects the event type and routes to the appropriate handler. 