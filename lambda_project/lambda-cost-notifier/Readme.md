# AWS Cost Notifier

A serverless solution that automatically sends daily AWS cost reports via email using Lambda, Cost Explorer, and SES.

## Overview

This project implements an automated daily cost notification system that:
- Queries AWS Cost Explorer for yesterday's spending
- Formats cost data into professional HTML/text emails
- Sends notifications via Amazon SES
- Prevents duplicate sends with DynamoDB tracking
- Monitors performance with CloudWatch alarms and dashboards

## Architecture

```
EventBridge (8 AM UTC) → Lambda Function → Cost Explorer API
                                      ↓
DynamoDB (tracking) ← SES (email) ← Email Formatter
                                      ↓
CloudWatch Logs ← CloudWatch Alarms → SNS → Email Alerts
```

## Features

- **Daily Automation**: Scheduled execution via EventBridge
- **Cost Analysis**: Retrieves and formats cost data by AWS service
- **Email Notifications**: Professional HTML emails with cost breakdowns
- **Idempotency**: Prevents duplicate emails using DynamoDB tracking
- **Error Handling**: Exponential backoff retry logic for API calls
- **Monitoring**: CloudWatch alarms for errors, performance, and missing executions
- **SLO Compliance**: 99.5% success rate with 30-second performance target
- **Security**: Least privilege IAM permissions

## File Structure

```
├── main.tf              # Core infrastructure (Lambda, IAM, EventBridge, SES)
├── monitoring.tf        # CloudWatch alarms, SNS alerts, dashboard
├── variables.tf         # Variable declarations with validation
├── terraform.tfvars     # Environment-specific configuration
├── src/
│   └── lambda_function.py  # Lambda function code
└── README.md           # This file
```

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Python 3.11+ (for local development/testing)
- Access to AWS Cost Explorer (requires billing access)

## Quick Start

### 1. Clone and Configure

```bash
git clone <repository>
cd aws-cost-notifier

# Copy and customize configuration
cp terraform.tfvars.example terraform.tfvars
```

### 2. Update Configuration

Edit `terraform.tfvars`:

```hcl
# Required: Update with your email addresses
admin_email  = "your-admin@company.com"    # Cost report recipient
sender_email = "noreply@yourcompany.com"   # Must be verified in SES
alert_email  = "alerts@company.com"        # Alert notifications

# Optional: Customize schedule and settings
schedule_expression = "cron(0 8 * * ? *)"  # 8 AM UTC daily
aws_region = "us-east-1"                   # Required for Cost Explorer
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply
```

### 4. Complete Email Verification

After deployment, check your email for SES verification links and click them for both sender and admin email addresses.

### 5. Test the Function

```bash
# Get function name from Terraform output
aws lambda invoke --function-name aws-cost-notifier output.json

# Check the response
cat output.json
```

## Configuration Options

### Email Settings

```hcl
admin_email  = "admin@company.com"        # Cost report recipient
sender_email = "noreply@company.com"      # From address (must verify in SES)
alert_email  = "alerts@company.com"       # CloudWatch alert recipient
ses_region   = "us-east-1"               # SES region
```

### Scheduling

```hcl
# Common schedule expressions:
schedule_expression = "cron(0 8 * * ? *)"   # 8 AM UTC daily
schedule_expression = "cron(0 14 * * ? *)"  # 9 AM EST daily
schedule_expression = "cron(0 8 ? * MON-FRI *)"  # Weekdays only
```

### Logging and Retention

```hcl
log_level         = "INFO"    # DEBUG, INFO, WARNING, ERROR, CRITICAL
log_retention_days = 30       # CloudWatch log retention period
```

## Monitoring and Alerts

### CloudWatch Alarms

The system includes comprehensive monitoring:

- **Lambda Errors**: Triggers on any function failure
- **Duration SLO Violation**: Alerts when execution exceeds 30 seconds
- **Timeout Warning**: Early warning at 55 seconds (60s timeout)
- **Missing Daily Execution**: Detects if scheduled function doesn't run
- **Email Bounces**: Monitors SES email delivery failures (if enabled)

### Dashboard

Access the CloudWatch dashboard at:
```
https://console.aws.amazon.com/cloudwatch/home#dashboards:name=aws-cost-notifier-dashboard
```

### Log Analysis

Query logs using CloudWatch Logs Insights:

```sql
# View recent executions
fields @timestamp, @message
| filter @message like /Starting cost notifier/
| sort @timestamp desc

# Find errors
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc

# SLO compliance
fields @timestamp, execution_time_seconds
| filter @message like /exceeded 30s SLO/
| sort @timestamp desc
```

## Cost Estimates

### Monthly AWS Costs (approximate)

- **Lambda**: ~$0.20 (1 execution/day, 512MB, ~10s runtime)
- **DynamoDB**: <$0.01 (minimal read/write operations)
- **CloudWatch Logs**: ~$0.50 (30-day retention)
- **CloudWatch Alarms**: ~$1.00 (5 alarms × $0.10/month)
- **SES**: <$0.01 (1 email/day within free tier)
- **EventBridge**: <$0.01 (1 rule, minimal usage)

**Total: ~$1.71/month**

## Troubleshooting

### Common Issues

**1. Email not sending**
```bash
# Check SES identities are verified
aws ses get-identity-verification-attributes --identities your-email@company.com

# Check Lambda logs
aws logs describe-log-streams --log-group-name "/aws/lambda/aws-cost-notifier"
```

**2. Cost data retrieval fails**
- Ensure IAM role has `ce:GetCostAndUsage` permission
- Verify Cost Explorer is enabled in AWS Billing console
- Check if running in supported region (Cost Explorer requires us-east-1)

**3. Function not executing**
```bash
# Check EventBridge rule status
aws events describe-rule --name aws-cost-notifier-daily-trigger

# Test manual invocation
aws lambda invoke --function-name aws-cost-notifier output.json
```

### Debugging Commands

```bash
# View recent Lambda executions
aws logs filter-log-events \
    --log-group-name "/aws/lambda/aws-cost-notifier" \
    --start-time $(date -d "1 day ago" +%s)000

# Check DynamoDB tracking records
aws dynamodb scan --table-name aws-cost-notifier-tracking

# View CloudWatch alarms
aws cloudwatch describe-alarms --alarm-name-prefix aws-cost-notifier
```

## Security Considerations

### IAM Permissions

The Lambda function uses least-privilege permissions:

- **CloudWatch Logs**: Write logs only to its own log group
- **Cost Explorer**: Read-only access to billing data
- **SES**: Send emails only from verified identities
- **DynamoDB**: Read/write only to tracking table
- **X-Ray**: Basic tracing permissions

### Data Privacy

- Cost data remains within your AWS account
- No external API calls or data transmission
- Tracking data stored in your DynamoDB table
- Logs retained according to your retention policy

## Maintenance

### Regular Tasks

- **Monthly**: Review CloudWatch costs and log retention
- **Quarterly**: Update Lambda runtime to latest version
- **As needed**: Rotate SES email addresses if required

### Updates

```bash
# Update Lambda function code
terraform apply -target=aws_lambda_function.cost_notifier

# Update monitoring configuration
terraform apply -target=module.monitoring

# Full infrastructure refresh
terraform apply -refresh-only
```

## Customization

### Modify Email Format

Edit `format_email()` function in `src/lambda_function.py`:

- Change number of top services displayed
- Add/remove cost metrics
- Modify HTML styling
- Include additional AWS service details

### Adjust Monitoring

Modify alarm thresholds in `monitoring.tf`:

- Change SLO target from 30 seconds
- Adjust evaluation periods
- Add custom metrics or alarms

### Schedule Changes

Update `schedule_expression` in `terraform.tfvars`:

- Change execution time
- Switch to weekdays only
- Add multiple schedules

## Support

For issues and questions:

1. Check CloudWatch logs and dashboard
2. Review troubleshooting section
3. Validate configuration in `terraform.tfvars`
4. Test individual components (SES, Cost Explorer, Lambda)

## License

This project is provided as-is for educational and operational use.