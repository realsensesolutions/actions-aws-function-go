# Datadog Integration Scope

## Overview

This document defines the scope of work for integrating Datadog observability into the `actions-aws-function-go` GitHub Action. The integration will provide automatic instrumentation for Go Lambda functions deployed through this action.

## Integration Goals

1. **Simplify Datadog setup** - Encapsulate all complexity within the action
2. **Automatic configuration** - Provision necessary AWS resources (Secrets Manager)
3. **Opt-in behavior** - Datadog integration is optional and disabled by default
4. **Architecture-aware** - Automatically select correct Datadog Extension layer based on ARM/x86
5. **Minimal user burden** - Only require Datadog API key as a GitHub secret

## Scope of Work

### 1. GitHub Action Inputs

Add the following new input to `action.yml`:

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `dd-tracing` | Enable Datadog tracing and observability | No | `false` |
| `dd-api-key` | Datadog API key from GitHub secrets | Yes (if `dd-tracing: true`) | N/A |

**Design Decisions:**
- No `DD_` prefix in input name for cleaner interface
- `dd-tracing` is the master switch to enable/disable all Datadog functionality
- **No dd-service, dd-env, dd-version inputs** - these are not Datadog-specific concepts and should be passed via the existing `env` input if needed by users
- Users can provide `DD_SERVICE`, `DD_ENV`, `DD_VERSION`, `DD_SITE` and any other Datadog configuration via the existing `env` input

### 2. AWS Resources to Provision

When `dd-tracing: true`, the action will:

#### 2.1 AWS Secrets Manager Secret

- **Resource**: AWS Secrets Manager secret to store Datadog API key
- **Naming**: `datadog-api-key` (shared across all Lambda functions)
- **Content**: Plain text string (not JSON) containing the Datadog API key value from `dd-api-key` input
- **Lifecycle**: 
  - Created if doesn't exist
  - Updated if exists with new value
  - **Never deleted** (persists even when Lambda is destroyed)
- **Implementation**: Bash script in GitHub Action step (NOT Terraform)

**Rationale for Step-based Approach:**
- One shared secret reduces costs and complexity
- Conditional creation logic is simpler in bash than Terraform
- Secret persists across Lambda function lifecycles
- No Terraform state conflicts when multiple functions share the secret
- Easier to handle idempotency (check if exists before create/update)

#### 2.2 IAM Permissions

Automatically add `secretsmanager:GetSecretValue` permission to Lambda execution role when Datadog is enabled.

**Implementation:** Modify the IAM policy generation logic in `main.tf` to include:
```hcl
{
  "Effect": "Allow",
  "Action": "secretsmanager:GetSecretValue",
  "Resource": "<secret-arn>"
}
```

### 3. Lambda Configuration

#### 3.1 Datadog Extension Layer

Add the Datadog Lambda Extension layer to the Lambda function.

**Layer ARN Format:**
```
# x86 (when arm: false)
arn:aws:lambda:<region>:464622532012:layer:Datadog-Extension:86

# ARM (when arm: true)
arn:aws:lambda:<region>:464622532012:layer:Datadog-Extension-ARM:86
```

**Implementation:** Add to `aws_lambda_function.layers` in `main.tf`

**Version:** Hardcoded to `86` (latest as of October 2024)

#### 3.2 Environment Variables

When Datadog is enabled, inject the following environment variables into the Lambda function:

| Variable | Value | Source |
|----------|-------|--------|
| `DD_SITE` | `datadoghq.com` | Hardcoded default (US1) |
| `DD_API_KEY_SECRET_ARN` | `<secret-arn>` | ARN of created secret |

**Note:** Users can provide any additional Datadog configuration (`DD_SERVICE`, `DD_ENV`, `DD_VERSION`, custom `DD_SITE`, etc.) using the existing `env` input

**Implementation:** Merge these into the existing environment variable map in `main.tf`

### 4. Terraform Changes

#### 4.1 New Variables (variables.tf)

```hcl
variable "dd_enabled" {
  description = "Enable Datadog tracing and observability"
  type        = bool
  default     = false
}

variable "dd_secret_arn" {
  description = "ARN of AWS Secrets Manager secret containing Datadog API key"
  type        = string
  default     = ""
}
```

**Note:** We only pass the secret ARN to Terraform, not the API key itself. The secret is managed by the GitHub Action step.

#### 4.2 New Resources

Create new Terraform file: `datadog.tf`

**Contents:**
1. Data source to get current AWS region (already exists in main.tf)
2. Locals for:
   - Datadog Extension layer ARN (architecture-aware)
   - Environment variables to inject

**Note:** Secret creation is handled by GitHub Action step, not Terraform

#### 4.3 Modified Resources

**`main.tf` - Lambda Function:**
- Add conditional layer to `layers` list
- Merge Datadog environment variables into `environment.variables`
- Add Secrets Manager permission to IAM role policy

### 5. GitHub Action Workflow Changes

#### 5.1 action.yml Composite Steps

Add new step to manage Secrets Manager secret **before Terraform init**.

**Step Order:**
1. Set up Go
2. Build Go Lambda function
3. **[NEW] Provision Datadog API Key secret** (if `dd-tracing: true`)
4. Terraform init
5. Terraform plan/destroy/apply

**New Step Implementation:**
```yaml
- name: Setup Datadog Secret
  id: datadog-secret
  if: inputs.dd-tracing == 'true'
  run: |
    # Check if secret exists
    SECRET_ARN=$(aws secretsmanager describe-secret --secret-id datadog-api-key --query ARN --output text 2>/dev/null || echo "")
    
    if [ -z "$SECRET_ARN" ]; then
      echo "Creating new Datadog API key secret..."
      SECRET_ARN=$(aws secretsmanager create-secret \
        --name datadog-api-key \
        --description "Datadog API key for Lambda observability" \
        --secret-string "${{ inputs.dd-api-key }}" \
        --query ARN --output text)
      echo "Created secret: $SECRET_ARN"
    else
      echo "Updating existing Datadog API key secret..."
      aws secretsmanager update-secret \
        --secret-id datadog-api-key \
        --secret-string "${{ inputs.dd-api-key }}"
      echo "Updated secret: $SECRET_ARN"
    fi
    
    echo "secret_arn=$SECRET_ARN" >> "$GITHUB_OUTPUT"
  shell: bash
```

**Modifications to Terraform steps:**
- Add new environment variables to all Terraform commands:
  ```yaml
  TF_VAR_dd_enabled: ${{ inputs.dd-tracing == 'true' }}
  TF_VAR_dd_secret_arn: ${{ steps.datadog-secret.outputs.secret_arn }}
  ```

### 6. User Experience

#### 6.1 Without Datadog (Default)

```yaml
- name: Deploy Lambda
  uses: realsensesolutions/actions-aws-function-go@main
  with:
    name: my-function
    working-directory: .
    entrypoint-file: main.go
```

No changes to existing behavior. Datadog is completely disabled.

#### 6.2 With Datadog Enabled (Minimal)

```yaml
- name: Deploy Lambda
  uses: realsensesolutions/actions-aws-function-go@main
  with:
    name: my-function
    working-directory: .
    entrypoint-file: main.go
    dd-tracing: true
    dd-api-key: ${{ secrets.DATADOG_API_KEY }}
```

#### 6.3 With Datadog and Custom Configuration

```yaml
- name: Deploy Lambda
  uses: realsensesolutions/actions-aws-function-go@main
  with:
    name: my-function
    working-directory: .
    entrypoint-file: main.go
    dd-tracing: true
    dd-api-key: ${{ secrets.DATADOG_API_KEY }}
    env: |
      DD_SERVICE: my-custom-service
      DD_ENV: staging
      DD_VERSION: ${{ github.sha }}
      DD_SITE: datadoghq.eu
      DD_LOGS_INJECTION: true
```

#### 6.4 Required User Code Changes

Users **must** modify their Lambda handler code to wrap it with Datadog's wrapper:

**Before:**
```go
package main

import (
    "context"
    "github.com/aws/aws-lambda-go/lambda"
)

func handler(ctx context.Context, event interface{}) (interface{}, error) {
    // handler logic
    return "ok", nil
}

func main() {
    lambda.Start(handler)
}
```

**After:**
```go
package main

import (
    "context"
    ddlambda "github.com/DataDog/datadog-lambda-go"
    "github.com/aws/aws-lambda-go/lambda"
)

func handler(ctx context.Context, event interface{}) (interface{}, error) {
    // handler logic
    return "ok", nil
}

func main() {
    lambda.Start(ddlambda.WrapFunction(handler, nil))
}
```

**Important:** This code change is **required** for distributed tracing but **optional** for basic metrics collection via the Extension layer.

### 7. Documentation Requirements

Update `README.md` with:

1. **New Inputs Section:** Document all Datadog inputs
2. **Datadog Integration Example:** Show complete example with code changes
3. **Prerequisites:** List requirement for `DATADOG_API_KEY` GitHub secret
4. **Troubleshooting:** Common issues and solutions
5. **Architecture Notes:** Explain automatic layer selection
6. **Code Requirements:** Clear instructions on handler wrapper

### 8. Out of Scope

The following items are **explicitly out of scope** for this integration:

1. **Custom Datadog Site Configuration:** Users can add `DD_SITE` via the `env` input if needed
2. **Datadog Extension Layer Version Updates:** Hardcoded to version 86; future updates require code change
3. **Advanced Datadog Configuration:** Users can add additional `DD_*` environment variables via `env` input
4. **Datadog Log Forwarder:** Not included; Extension sends data directly to Datadog
5. **FIPS Compliance:** Not configured by default
6. **VPC PrivateLink:** Users must configure separately if needed
7. **Automatic Code Wrapping:** Users must manually wrap their handler functions
8. **Custom Metrics/Spans:** Users add these in their code; action only provides infrastructure
9. **Datadog APM Profiling:** Users can enable via environment variables if needed

### 9. Testing Strategy

#### 9.1 E2E Testing via GitHub Actions

**Test Infrastructure:**
- Test file: `.github/workflows/example.yml`
- Example Lambda: `examples/main.go`
- Test by running the workflow with different configurations

**Test Scenarios:**

1. **Baseline (Datadog disabled):** 
   - Run existing workflow without changes
   - Verify Lambda deploys and functions correctly
   - This ensures we don't break existing functionality

2. **Datadog enabled - minimal config:**
   ```yaml
   - name: Deploy Lambda with Datadog
     uses: ./
     with:
       name: demo-datadog
       working-directory: examples
       entrypoint-file: main.go
       dd-tracing: true
       dd-api-key: ${{ secrets.DATADOG_API_KEY }}
   ```

3. **Datadog enabled - with custom env vars:**
   ```yaml
   - name: Deploy Lambda with Datadog Custom
     uses: ./
     with:
       name: demo-datadog-custom
       working-directory: examples
       entrypoint-file: main.go
       dd-tracing: true
       dd-api-key: ${{ secrets.DATADOG_API_KEY }}
       env: |
         DD_SERVICE: custom-service
         DD_ENV: staging
         DD_VERSION: v1.0.0
   ```

4. **ARM vs x86 architecture:**
   - Test with `arm: true` and `arm: false`
   - Verify correct layer ARN selection

5. **Secret persistence:**
   - Deploy once, verify secret created
   - Deploy again, verify secret updated (no errors)
   - Deploy with different API key, verify secret updated

6. **Worker mode + Datadog:**
   - Deploy with `worker: true` and `dd-tracing: true`
   - Verify both SQS and Datadog work together

#### 9.2 Validation Checklist

After each E2E test deployment, manually verify:

- [ ] Secrets Manager secret `datadog-api-key` exists
- [ ] Secret contains correct API key value (plain text)
- [ ] Lambda function has Datadog Extension layer attached
- [ ] Lambda has `DD_SITE` and `DD_API_KEY_SECRET_ARN` environment variables
- [ ] Lambda IAM role has `secretsmanager:GetSecretValue` permission
- [ ] Lambda function executes successfully (check CloudWatch Logs)
- [ ] No Datadog-related errors in CloudWatch Logs
- [ ] (Optional) If handler is wrapped, verify traces appear in Datadog

#### 9.3 Example Lambda Code Update

Update `examples/main.go` to demonstrate Datadog wrapper (optional for testing):

```go
// Add to imports
import ddlambda "github.com/DataDog/datadog-lambda-go"

// Change main function
func main() {
    // Check if Datadog is enabled via environment variable
    if os.Getenv("DD_API_KEY_SECRET_ARN") != "" {
        lambda.Start(ddlambda.WrapFunction(router, nil))
    } else {
        lambda.Start(router)
    }
}
```

This allows testing both scenarios without breaking existing functionality.

### 10. Implementation Order

Recommended implementation sequence:

1. **Update `variables.tf`** - Add Datadog variables (`dd_enabled`, `dd_secret_arn`)
2. **Create `datadog.tf`** - Define Datadog-specific Terraform resources (layer, env vars)
3. **Update `main.tf`** - Integrate Datadog layer and environment variables
4. **Update IAM policies in `main.tf`** - Add Secrets Manager permission conditionally
5. **Update `action.yml`** - Add inputs and new step for secret management
6. **Update `example.yml`** - Add Datadog example (commented out initially)
7. **E2E test** - Run GitHub Actions workflow to validate
8. **Update `examples/main.go`** - Add conditional Datadog wrapper for demo
9. **Update `README.md`** - Document integration with examples
10. **Final E2E validation** - Test all scenarios

### 11. Decisions Made

1. **✅ Shared Secret:** Using one shared secret `datadog-api-key` across all Lambda functions
   - Reduces costs ($0.40/month per secret)
   - Simpler management
   - One API key for all observability
   
2. **✅ Secret Managed by GitHub Action:** Bash script checks/creates/updates secret
   - Not managed by Terraform
   - Persists across Lambda lifecycle
   - Never deleted (even when Lambda is destroyed)

3. **✅ No DD-specific Inputs:** Only `dd-tracing` and `dd-api-key`
   - Users configure `DD_SERVICE`, `DD_ENV`, `DD_VERSION` via existing `env` input
   - These are generic concepts, not Datadog-exclusive

4. **✅ Layer Version:** Hardcoded to version 86
   - Manual updates in code when new versions released
   - Document in CHANGELOG

5. **✅ Error Handling:** Script/Terraform will fail with clear error messages
   - User must fix configuration and retry
   - Secrets Manager API errors will be visible in GitHub Actions logs

### 12. Success Criteria

The integration is considered successful when:

1. ✅ Users can enable Datadog with just `dd-tracing: true` and `dd-api-key: ${{ secrets.DATADOG_API_KEY }}`
2. ✅ All AWS resources (secret, layer, IAM permissions) are provisioned automatically
3. ✅ Correct Datadog Extension layer is selected based on architecture
4. ✅ Lambda functions with wrapped handlers send traces to Datadog
5. ✅ Lambda functions without wrapped handlers still send basic metrics via Extension
6. ✅ Integration is completely optional and doesn't affect existing users
7. ✅ Documentation clearly explains setup and code requirements
8. ✅ Example workflow demonstrates Datadog integration

---

## Next Steps

Once this scope is approved:
1. Review and confirm all decisions
2. Proceed with implementation following the defined order
3. Create PR with all changes
4. Validate against testing strategy
5. Update documentation and examples

