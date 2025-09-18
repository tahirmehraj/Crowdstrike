# AWS Cost Notifier - Architecture Guide

## System Overview

Serverless, event-driven cost notification system built on AWS managed services with comprehensive observability and 99.5% availability SLO.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AWS COST NOTIFIER ARCHITECTURE                     │
└─────────────────────────────────────────────────────────────────────────────┘

    SCHEDULING              PROCESSING               DATA SOURCES
┌───────────────┐      ┌────────────────┐      ┌──────────────────┐
│  EventBridge  │────▶ │ Lambda Function│────▶ │ AWS Cost Explorer│
│ 0 8 * * ? *   │      │ Python 3.11    │      │ get_cost_and_usage│
│ (8 AM UTC)    │      │ 60s timeout    │      │ Group by SERVICE │
└───────────────┘      └────────────────┘      └──────────────────┘
                                │
                                ▼
    STATE MANAGEMENT       EMAIL DELIVERY         MONITORING STACK
┌───────────────┐      ┌────────────────┐      ┌──────────────────┐
│   DynamoDB    │◀────▶│  Amazon SES    │      │  CloudWatch      │
│ Tracking Table│      │ HTML + Text    │      │ Logs + 5 Alarms  │
│ Idempotency   │      │ admin@company  │      │ Dashboard + SNS  │
└───────────────┘      └────────────────┘      └──────────────────┘
```

## Component Specifications

### Core Processing Stack
| Component | Specification | Purpose |
|-----------|---------------|---------|
| **Lambda Function** | Python 3.11, 512MB, 60s timeout | Cost data processing and email formatting |
| **EventBridge** | Cron: `0 8 * * ? *` (8 AM UTC daily) | Reliable scheduling trigger |
| **Cost Explorer** | `get_cost_and_usage` API, us-east-1 | AWS spending data source |
| **DynamoDB** | On-demand, `report_date` PK | Idempotency and execution tracking |
| **SES** | HTML/Text multipart emails | Professional cost report delivery |

### Monitoring & Alerting
| Component | Configuration | SLO Impact |
|-----------|---------------|------------|
| **CloudWatch Alarms** | 5 alarms (Errors, Duration, Missing, Timeout, Bounces) | 99.5% availability monitoring |
| **SNS Topic** | Email alerts to operations team | Incident response automation |
| **Dashboard** | Lambda metrics + error log queries | Operational visibility |
| **Log Retention** | 30 days, structured JSON | Troubleshooting and analysis |

## Data Flow & Error Handling

### Normal Execution Flow
1. **EventBridge** → Lambda invocation (8 AM UTC daily)
2. **Lambda** → DynamoDB check (already sent today?)
3. **Lambda** → Cost Explorer API (yesterday's costs by service)  
4. **Lambda** → SES email delivery (HTML + text format)
5. **Lambda** → DynamoDB record (mark as sent, store message ID)
6. **All operations** → CloudWatch logging and metrics

### Retry & Recovery Strategy
```python
# Exponential backoff implementation
for attempt in range(3):  # 3 attempts as specified
    try:
        return api_call()
    except RetryableError:
        wait_time = 2 ** attempt  # 1s, 2s, 4s delays
        time.sleep(wait_time)
```

**Retryable scenarios**:
- Cost Explorer API throttling
- SES rate limiting  
- DynamoDB conditional write failures
- Transient network errors

## Security Architecture

### IAM Permissions (Least Privilege)
```json
{
  "CloudWatch": "Write logs to own log group only",
  "Cost Explorer": "Read-only billing data access", 
  "SES": "Send from verified identities only",
  "DynamoDB": "Read/write tracking table only",
  "X-Ray": "Basic tracing permissions"
}
```

### Data Protection
- **Encryption in-transit**: TLS 1.2+ for all AWS API communications
- **Encryption at-rest**: AWS service defaults (not explicitly configured)
  - DynamoDB: Default encryption enabled by AWS
  - CloudWatch Logs: No KMS key configured (AWS managed)
  - Lambda environment variables: Default AWS encryption
- **Network**: All AWS managed services, no VPC required
- **Secrets**: No sensitive data in code, configuration via environment variables only
- **Access Control**: Account-boundary isolation, no cross-account access

### Security Considerations
**Current implementation relies on AWS service defaults for data protection.** 
For enhanced security compliance:
- Add explicit KMS keys for DynamoDB and CloudWatch Logs
- Enable customer-managed encryption for Lambda environment variables
- Implement VPC endpoints for API calls (if network isolation required)

## Scalability & Performance

### Current Design Targets
- **Concurrency**: Single daily execution, no scaling needed
- **Performance**: 8-12 second typical execution (30s SLO target)
- **Reliability**: 99.5% success rate (1 failure every 2 months)
- **Cost**: ~$1.71/month with current configuration

### Scaling Considerations
**Vertical scaling** (if needed):
- Memory: 512MB → 1024MB for faster execution
- Timeout: 60s adequate for retry logic

**Horizontal scaling** (future features):
- Multiple schedules via additional EventBridge rules
- Per-team cost notifications using Lambda concurrency
- Cost anomaly detection with real-time triggers

## Operational Integration

### Infrastructure as Code
```hcl
# Terraform module structure
├── main.tf          # Core infrastructure (Lambda, IAM, EventBridge, SES)
├── monitoring.tf    # CloudWatch alarms, SNS, dashboard  
├── variables.tf     # Input validation and defaults
└── terraform.tfvars # Environment-specific configuration
```

### Monitoring Integration
- **Built-in metrics**: Lambda standard metrics (no custom metrics needed)
- **Log analysis**: CloudWatch Logs Insights for troubleshooting
- **Alert routing**: SNS → Email → Operations team workflow
- **Dashboard access**: Real-time system health visualization

## Design Decisions & Trade-offs

### Architecture Choices
| Decision | Rationale | Trade-off |
|----------|-----------|-----------|
| **Serverless over EC2** | Cost efficiency, no maintenance | Cold start latency (minimal impact) |
| **EventBridge over CloudWatch** | Better debugging, extensibility | Slightly higher complexity |
| **DynamoDB over RDS** | Serverless consistency, cost | Limited query patterns |
| **Built-in metrics vs custom** | Operational simplicity | Less granular business metrics |

### Cost vs Reliability Balance
- **99.5% SLO**: Balances reliability with cost for non-critical reporting
- **Single region**: Cost optimization over maximum availability  
- **On-demand scaling**: Pay-per-use over reserved capacity
- **30-day log retention**: Operational needs vs storage costs

## Extension Points

### Immediate Enhancements
- **Slack notifications**: SNS → Lambda → Slack webhook
- **Cost anomaly detection**: Compare current vs historical spending
- **Multi-team reports**: Separate cost breakdowns by tags/accounts

### Advanced Integrations  
- **Budget integration**: AWS Budgets API for threshold alerts
- **FinOps dashboard**: Cost trends and optimization recommendations
- **Multi-cloud support**: Azure/GCP cost APIs for hybrid environments

This architecture provides a robust foundation for automated cost reporting while maintaining operational simplicity and cost efficiency.