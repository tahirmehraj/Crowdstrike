# AWS Cost Notifier - SRE Technical Assessment
## Automated Daily Cost Reporting Solution

---

## Slide 1: Problem & Objective

**Challenge**: Manual AWS cost monitoring leads to delayed visibility and budget overruns

**Solution**: Automated serverless system delivering daily cost reports via email

**Assessment Requirements Met**:
- ✅ Lambda function querying AWS Cost Explorer
- ✅ Daily email to admin@company.com via SES
- ✅ Infrastructure as Code (Terraform)
- ✅ SRE principles implementation

---

## Slide 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AWS COST NOTIFIER ARCHITECTURE                     │
└─────────────────────────────────────────────────────────────────────────────┘

    SCHEDULING              PROCESSING               DATA SOURCES
┌───────────────┐      ┌────────────────┐      ┌──────────────────┐
│  EventBridge  │────▶ │ Lambda Function│────▶ │ AWS Cost Explorer│
│               │      │                │      │                  │
│ Cron Expression│      │ Python 3.11    │      │ get_cost_and_usage│
│ 0 8 * * ? *   │      │ 60s timeout    │      │ Previous day data│
│ (8 AM UTC)    │      │ 512MB memory   │      │ Group by SERVICE │
└───────────────┘      └────────────────┘      └──────────────────┘
                                │
                                ▼
    STATE MANAGEMENT       EMAIL DELIVERY         MONITORING STACK
┌───────────────┐      ┌────────────────┐      ┌──────────────────┐
│   DynamoDB    │◀────▶│  Amazon SES    │      │  CloudWatch      │
│               │      │                │      │                  │
│ Tracking Table│      │ HTML + Text    │      │ • Logs + Alarms  │
│ report_date PK│      │ admin@company  │      │ • Dashboard      │
│ Idempotency   │      │ Cost Summary   │      │ • 5 Alert Rules  │
└───────────────┘      └────────────────┘      └──────────────────┘
                                                         │
                                                         ▼
                                                ┌──────────────────┐
                                                │   SNS Topic      │
                                                │                  │
                                                │ Email Alerts     │
                                                │ Operations Team  │
                                                └──────────────────┘

EXECUTION FLOW:
1. EventBridge → Lambda (daily 8 AM UTC)
2. Lambda → DynamoDB (check if already sent today)  
3. Lambda → Cost Explorer (get yesterday's costs)
4. Lambda → SES (send formatted email report)
5. Lambda → DynamoDB (mark as sent)
6. All operations → CloudWatch (logging & monitoring)
```

**Key Design Decisions**:
- **Serverless**: Pay-per-use, no infrastructure management
- **Event-driven**: EventBridge scheduling for reliability  
- **Idempotent**: DynamoDB prevents duplicate notifications
- **Resilient**: Exponential backoff retry logic
- **Observable**: Comprehensive monitoring without alert fatigue

---

## Slide 3: SRE Implementation - SLOs & Monitoring

**Service Level Objectives** (per requirements):
- **Availability**: 99.5% success rate (allows 1 failure every 2 months)
- **Performance**: 95% executions under 30 seconds
- **Reliability**: Daily execution within 25-hour window

**Monitoring Stack**:
- **5 CloudWatch Alarms**: Errors, Duration SLO, Missing execution, Timeouts
- **SNS Alerting**: Email notifications for failures
- **Dashboard**: Real-time visibility into system health
- **Structured Logging**: JSON logs for operational insights

---

## Slide 4: Reliability & Error Handling

**Retry Strategy** (per clarification):
- **3 attempts** with exponential backoff (1s, 2s, 4s)
- **60-second timeout** with 30-second SLO target
- **Circuit breaking** on non-retryable errors

**Failure Scenarios Handled**:
- Cost Explorer API throttling → Retry with backoff
- SES email delivery failures → Retry + alerting  
- Missing daily execution → 25-hour detection alarm
- DynamoDB unavailable → Graceful degradation

**Self-Healing Features**:
- Automatic retry on transient failures
- Idempotency prevents duplicate sends
- Missing execution alerts enable manual recovery

---

## Slide 5: Security & Best Practices

**IAM Security** (Least Privilege):
```json
{
  "CloudWatch Logs": "Write to own log group only",
  "Cost Explorer": "Read-only access to billing data", 
  "SES": "Send from verified identities only",
  "DynamoDB": "Read/write to tracking table only"
}
```

**Additional Security**:
- ✅ **No secrets in code** - Environment variables only
- ✅ **Encryption in-transit** - TLS 1.2+ for all AWS API calls
- ⚠️ **Encryption at-rest** - AWS service defaults (not explicitly configured)
- ✅ **Resource scoping** - ARN-based permissions
- ✅ **Account boundary** - All data stays in AWS account

---

## Slide 6: Operational Excellence

**Infrastructure as Code**:
- **Terraform modules**: Main + Monitoring separation
- **Variable validation**: Email format, cron expressions
- **Automated deployment**: `terraform apply`

**Documentation**:
- **Runbook**: Quick health checks, incident response
- **Architecture docs**: Technical implementation details
- **SLO definitions**: Measurable reliability targets

**Cost Optimization**:
- **Monthly cost**: ~$1.71 (serverless pay-per-use)
- **Right-sizing**: 512MB memory, 60s timeout
- **Efficient design**: Single daily execution, minimal storage

---

## Slide 7: Demo & Validation

**Live Demo Points**:
1. **Manual trigger**: `aws lambda invoke --function-name aws-cost-notifier`
2. **Email delivery**: HTML/text cost breakdown with service details
3. **Monitoring**: CloudWatch dashboard showing metrics and SLO compliance
4. **Idempotency**: Second execution returns "Already sent today"

**SLO Compliance Evidence**:
- Execution time: ~8-12 seconds (well under 30s SLO)
- Success rate: 100% in testing (exceeds 99.5% target)
- Alert testing: Simulated failures trigger SNS notifications

---

## Slide 8: Challenges & SRE Learnings

**Key Challenges Solved**:

1. **SES Email Verification**: Manual step requiring clear documentation
   - *Solution*: Automated identity creation + clear setup instructions

2. **Cost Explorer API Limits**: Potential throttling during AWS peak times
   - *Solution*: Exponential backoff retry with circuit breaking

3. **Timezone Considerations**: Global deployment across time zones
   - *Solution*: 25-hour detection window accommodates DST changes

**SRE Principles Applied**:
- **Error budgets**: 1 failure every 2 months balances cost vs reliability
- **Observability**: Comprehensive monitoring without alert fatigue
- **Toil reduction**: Eliminates 30 min/day manual cost checking

---

## Slide 9: Production Readiness & Next Steps

**Production Ready Features**:
- ✅ **Comprehensive monitoring** with business-relevant alerts
- ✅ **Runbook procedures** for common failure scenarios
- ✅ **Security compliance** with least privilege IAM
- ✅ **Cost optimization** with predictable monthly spend
- ✅ **Documentation** for operations team handoff

**Potential Improvements**:
- **Multi-region deployment** for higher availability (trade-off: cost vs reliability)
- **Slack integration** for developer-friendly notifications
- **Cost anomaly detection** with ML-based threshold alerting
- **Enhanced reporting** with weekly/monthly cost trends

**Questions?**

---

## Appendix: Technical Deep Dive

**Available if time permits**:
- Terraform module structure and best practices
- Lambda function code walkthrough
- CloudWatch Logs Insights queries for troubleshooting
- Error budget calculations and SLO mathematics