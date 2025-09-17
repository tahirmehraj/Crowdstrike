# AWS Cost Notifier - Operations Runbook

## Quick Health Check

```bash
# Check yesterday's execution
aws logs describe-log-streams --log-group-name "/aws/lambda/aws-cost-notifier" --order-by LastEventTime --descending --max-items 1

# Verify tracking record
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
aws dynamodb get-item --table-name aws-cost-notifier-tracking --key '{"report_date":{"S":"'$YESTERDAY'"}}'
```

## Incident Response

### Lambda Errors Alarm

**Check recent errors:**
```bash
aws logs filter-log-events --log-group-name "/aws/lambda/aws-cost-notifier" --start-time $(date -d "2 hours ago" +%s)000 --filter-pattern "ERROR"
```

**Common fixes:**
- SES email unverified: Click verification links in email
- Manual retry: `aws lambda invoke --function-name aws-cost-notifier output.json`

### Missing Execution Alarm

**Check EventBridge rule:**
```bash
aws events describe-rule --name aws-cost-notifier-daily-trigger
```

**Fix:**
```bash
# Enable rule if disabled
aws events enable-rule --name aws-cost-notifier-daily-trigger

# Manual trigger
aws lambda invoke --function-name aws-cost-notifier output.json
```

### Duration SLO Violation

Usually Cost Explorer API delays. Monitor for auto-resolution within 30 minutes.

### Email Bounces

**Check SES status:**
```bash
aws ses get-send-statistics --region us-east-1
```

Hard bounces: Update email in terraform.tfvars and redeploy.

## Manual Operations

### Force Resend Report
```bash
# Clear tracking record
TARGET_DATE="2024-09-16" 
aws dynamodb delete-item --table-name aws-cost-notifier-tracking --key '{"report_date":{"S":"'$TARGET_DATE'"}}'

# Trigger execution
aws lambda invoke --function-name aws-cost-notifier output.json
```

### Manual Cost Report
```bash
aws lambda invoke --function-name aws-cost-notifier --payload '{"trigger_type":"manual"}' output.json
```

## Emergency Recovery

If Lambda completely fails:

```bash
# Get costs manually
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)
aws ce get-cost-and-usage --time-period Start=$YESTERDAY,End=$TODAY --granularity DAILY --metrics BlendedCost --group-by Type=DIMENSION,Key=SERVICE --region us-east-1

# Send manual email
aws ses send-email --source noreply@company.com --destination ToAddresses=admin@company.com --message Subject.Data="Manual Cost Report",Body.Text.Data="See AWS console for details" --region us-east-1
```

## Monitoring Queries

**Recent executions:**
```sql
fields @timestamp, @message | filter @message like /Starting cost notifier/ | sort @timestamp desc | limit 10
```

**Errors:**
```sql
fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc
```

**Performance:**
```sql
fields @timestamp, execution_time_seconds | filter @message like /completed successfully/ | sort @timestamp desc
```

## Key Resources

- Dashboard: `aws-cost-notifier-dashboard`
- Function: `aws-cost-notifier` 
- Table: `aws-cost-notifier-tracking`
- Alarms: `aws-cost-notifier-*`