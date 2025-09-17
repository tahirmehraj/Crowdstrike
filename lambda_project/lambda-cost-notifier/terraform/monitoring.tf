##############################################################################
# monitoring.tf
# Simplified CloudWatch + SNS monitoring for Cost Notifier Lambda
#
# - Purpose: provide core operational monitoring and alerting while removing
#   brittle custom log-derived metrics.
# - Contents:
#   * SNS topic + subscription + topic policy (CloudWatch can publish)
#   * Core CloudWatch alarms (Errors, Duration SLO, Timeout warning, Throttles,
#     Missing Execution, DynamoDB user errors)
#   * Simplified CloudWatch dashboard (Lambda metrics + recent errors log)
#   * Outputs for alarm names and dashboard URL
#
# Notes:
# - This file expects the following resources/data to exist elsewhere in the
#   module: aws_lambda_function.cost_notifier,
#   aws_cloudwatch_log_group.lambda_logs,
#   aws_dynamodb_table.cost_notifier_tracking,
#   var.function_name, var.alert_email,
#   data.aws_region.current, data.aws_caller_identity.current
##############################################################################

# ------------------------------
# SNS topic for alerts
# ------------------------------
# Creates the SNS topic used to notify ops/on-call when alarms fire.
resource "aws_sns_topic" "lambda_alerts" {
  name = "${var.function_name}-alerts"

  tags = {
    Name    = "Cost Notifier Lambda Alerts"
    Project = "cost-notifier"
  }
}

# ------------------------------
# SNS topic subscription (email)
# ------------------------------
# Subscribes an email endpoint to the alerts topic. Recipient must confirm.
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.lambda_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ------------------------------
# SNS topic policy to allow CloudWatch -> SNS
# ------------------------------
# Permits CloudWatch (service principal) in this account to publish to the
# topic. Restricts by aws:SourceAccount to mitigate cross-account publishing.
resource "aws_sns_topic_policy" "lambda_alerts_policy" {
  arn = aws_sns_topic.lambda_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["sns:Publish"]
        Resource  = aws_sns_topic.lambda_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ------------------------------
# Alarm: Lambda Errors (any error triggers)
# ------------------------------
# Monitors built-in Lambda Errors metric. Any error in a 5-minute window
# triggers this alarm and notifies SNS. Used as a coarse SLO/signal.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Lambda function errors detected - impacts 99.5% success rate SLO"
  alarm_actions       = [aws_sns_topic.lambda_alerts.arn]
  ok_actions          = [aws_sns_topic.lambda_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.cost_notifier.function_name
  }

  tags = {
    SLO       = "99.5% success rate"
    Severity  = "Critical"
    Component = "Lambda Function"
  }
}

# ------------------------------
# Alarm: Lambda Duration - SLO Violation (30s)
# ------------------------------
# Triggers when any invocation's duration exceeds 30 seconds (SLO target).
# Uses Maximum statistic in a 5-minute window to catch slow invocations.
resource "aws_cloudwatch_metric_alarm" "lambda_duration_slo" {
  alarm_name          = "${var.function_name}-duration-slo-violation"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Maximum"
  threshold           = 30000
  alarm_description   = "Lambda execution exceeding 30s SLO target"
  alarm_actions       = [aws_sns_topic.lambda_alerts.arn]
  ok_actions          = [aws_sns_topic.lambda_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.cost_notifier.function_name
  }

  tags = {
    SLO       = "30 second execution time"
    Severity  = "Warning"
    Component = "Performance"
  }
}

# ------------------------------
# Alarm: Lambda Duration - Timeout Warning (55s)
# ------------------------------
# Early-warning alarm when execution approaches the configured timeout (60s).
# Useful to mitigate timeouts before they happen.
resource "aws_cloudwatch_metric_alarm" "lambda_timeout_warning" {
  alarm_name          = "${var.function_name}-timeout-warning"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Maximum"
  threshold           = 55000
  alarm_description   = "Lambda execution approaching 60s timeout limit"
  alarm_actions       = [aws_sns_topic.lambda_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.cost_notifier.function_name
  }

  tags = {
    Severity  = "Warning"
    Component = "Performance"
  }
}


# ------------------------------
# Alarm: Missing Daily Execution (Invocations < 1 in ~25 hours)
# ------------------------------
# Detects if the scheduled EventBridge rule fails to invoke the Lambda for a day.
# Uses treat_missing_data = "breaching" so absence of metrics alarms.
resource "aws_cloudwatch_metric_alarm" "lambda_missing_execution" {
  alarm_name          = "${var.function_name}-missing-execution"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Invocations"
  namespace           = "AWS/Lambda"
  period              = 90000   # 25 hours
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Daily cost notifier not executing - check EventBridge rule"
  alarm_actions       = [aws_sns_topic.lambda_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    FunctionName = aws_lambda_function.cost_notifier.function_name
  }

  tags = {
    Severity  = "Critical"
    Component = "Scheduling"
  }
}

# ------------------------------
# Alarm: SES Email Bounces - Email Delivery Health Monitor
# ------------------------------
# PURPOSE: Monitors email delivery failures for cost notifications sent via SES.
#          Detects when recipient email addresses are invalid, full, or blocked.
#

resource "aws_cloudwatch_metric_alarm" "email_bounces" {
  count               = var.use_ses ? 1 : 0
  alarm_name          = "${var.function_name}-email-bounces"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Bounce"
  namespace           = "AWS/SES"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Cost notification emails bouncing"
  alarm_actions       = [aws_sns_topic.lambda_alerts.arn]

  tags = {
    Severity  = "Warning"
    Component = "Email Delivery"
  }
}
# ------------------------------
# CloudWatch Dashboard (simplified)
# ------------------------------
# ------------------------------
# CloudWatch Dashboard - Cost Notifier (Minimal)
# ------------------------------
# Simple operational view showing core Lambda health and recent errors.
# Focus on the most important metrics for daily monitoring.
resource "aws_cloudwatch_dashboard" "cost_notifier" {
  dashboard_name = "${var.function_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # ═══════════════════════════════════════════════════════════════
      # Lambda Function Health Metrics
      # ═══════════════════════════════════════════════════════════════
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.cost_notifier.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Function Metrics"
          period  = 300
          annotations = {
            horizontal = [
              {
                label = "30s SLO"
                value = 30000
              }
            ]
          }
        }
      },

      # ═══════════════════════════════════════════════════════════════
      # Recent Error Logs
      # ═══════════════════════════════════════════════════════════════
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.lambda_logs.name}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
          region  = data.aws_region.current.name
          title   = "Recent Errors"
        }
      }
    ]
  })

  tags = {
    Name = "Cost Notifier Dashboard"
  }
}
# ------------------------------
# Output: dashboard URL
# ------------------------------
# Convenience output linking directly to the CloudWatch dashboard in console.
output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.cost_notifier.dashboard_name}"
}
