# AWS Cost Notifier Lambda - Main Terraform Configuration
# =======================================================
#
# This configuration implements all requirements from the technical assessment:
#
# Original Requirements:
# ✓ Lambda function that queries AWS Cost Explorer
# ✓ Daily email summary via Amazon SES to admin@company.com
# ✓ Infrastructure as Code setup for Lambda and supporting resources
# ✓ SLOs, monitoring metrics, alert thresholds
# ✓ Runbooks for common failures
# ✓ Security best practices (IAM, encryption, least privilege)
#
# Interviewer Clarifications:
# ✓ Scheduled to run automatically triggered by event (EventBridge)
# ✓ Target SLO: 99.5% success rate with maximum execution time of 30 seconds
# ✓ Lambda timeout should be set to 60 seconds to allow for retry logic
# ✓ Include basic CloudWatch alarms in Terraform setup
# ✓ Set up SNS topic for alerting on failures
# ✓ Implement exponential backoff retry logic (3 attempts) for transient failures
# ✓ Log all errors to CloudWatch Logs and send alerts for persistent failures

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cost-notifier"
      Environment = var.environment
      ManagedBy   = "terraform"
      Purpose     = "SRE-technical-assessment"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Create deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/lambda_deployment.zip"
}

# CloudWatch Log Group (create before Lambda function)
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "Cost Notifier Lambda Logs"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.function_name}-execution-role"

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

  tags = {
    Name = "Cost Notifier Lambda Execution Role"
  }
}

# IAM Policy for Lambda (Least Privilege)
# ------------------------------
# IAM Policy for Lambda (Least Privilege)
# ------------------------------
# Defines exact permissions needed for cost notification function.
# Follows security best practice: minimal permissions, specific resources only.
resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.function_name}-policy"
  description = "IAM policy for Cost Notifier Lambda function with least privilege access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs permissions
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",    # Create new log stream per execution
          "logs:PutLogEvents"        # Write log messages (INFO, ERROR, etc.)
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_logs.arn}:*"  # Only this function's logs
      },
      # Cost Explorer permissions (minimal required)
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",      # Main API for cost data retrieval
          "ce:GetUsageReport"        # Additional usage statistics
        ]
        Resource = "*"  # Cost Explorer doesn't support resource-level permissions
      },
      # SES permissions (scoped to verified identities)
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",           # Send formatted emails
          "ses:SendRawEmail",        # Send raw MIME emails
          "ses:GetSendQuota",        # Check daily sending limits
          "ses:GetSendStatistics"    # Monitor bounce/complaint rates
        ]
        Resource = [
          # Only verified email addresses (prevents spoofing)
          "arn:aws:ses:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:identity/${var.admin_email}",
          "arn:aws:ses:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:identity/${var.sender_email}"
        ]
      },
      # X-Ray tracing permissions
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",    # Send execution traces for performance monitoring
          "xray:PutTelemetryRecords"  # Send performance metrics
        ]
        Resource = "*"  # X-Ray doesn't use resource-specific permissions
      },
      # DynamoDB permissions for idempotency tracking
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",        # Check if notification already sent today
          "dynamodb:PutItem"         # Record execution to prevent duplicates
        ]
        Resource = aws_dynamodb_table.cost_notifier_tracking.arn  # Only tracking table
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# DynamoDB table for tracking sent reports (idempotency)
resource "aws_dynamodb_table" "cost_notifier_tracking" {
  name           = "${var.function_name}-tracking"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "report_date"

  attribute {
    name = "report_date"
    type = "S"
  }

  tags = {
    Name = "Cost Notifier Tracking Table"
  }
}

# Lambda Function
resource "aws_lambda_function" "cost_notifier" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"

  # Interviewer Requirements
  timeout     = 60   # 60 seconds as specified (allows retry buffer)
  memory_size = 512  # Sufficient for API calls and email formatting


  # Enable X-Ray tracing for debugging
  tracing_config {
    mode = "Active"
  }

  # Environment variables include DynamoDB table name
  environment {
    variables = {
      ADMIN_EMAIL     = var.admin_email
      SENDER_EMAIL    = var.sender_email
      SES_REGION      = var.ses_region
      LOG_LEVEL       = var.log_level
      TRACKING_TABLE  = aws_dynamodb_table.cost_notifier_tracking.name
    }
  }

  # Ensure dependencies are created first
  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  # Force redeployment when code changes
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = {
    Name = "Cost Notifier Lambda Function"
  }
}

# EventBridge rule for daily scheduling
resource "aws_cloudwatch_event_rule" "daily_cost_report" {
  name                = "${var.function_name}-daily-trigger"
  description         = "Trigger cost notifier daily at specified time"
  schedule_expression = var.schedule_expression  # Default: "cron(0 8 * * ? *)" - 8 AM UTC daily
  state              = "ENABLED"

  tags = {
    Name = "Daily Cost Report Trigger"
  }
}

# EventBridge target - Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_cost_report.name
  target_id = "CostNotifierLambdaTarget"
  arn       = aws_lambda_function.cost_notifier.arn

  # Pass metadata to Lambda function
  input_transformer {
    input_paths = {
      timestamp = "$.time"
    }
    input_template = jsonencode({
      trigger_type = "scheduled"
      timestamp    = "<timestamp>"
    })
  }
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_notifier.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_cost_report.arn
}

# SES Email Identity Verification (for sender)
resource "aws_ses_email_identity" "sender" {
  email = var.sender_email
}

# SES Email Identity Verification (for admin recipient)
resource "aws_ses_email_identity" "admin" {
  email = var.admin_email
}

# Output important information
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.cost_notifier.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.cost_notifier.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.daily_cost_report.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.lambda_alerts.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB tracking table"
  value       = aws_dynamodb_table.cost_notifier_tracking.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "ses_identities" {
  description = "SES email identities that need verification"
  value = {
    sender = aws_ses_email_identity.sender.email
    admin  = aws_ses_email_identity.admin.email
  }
}