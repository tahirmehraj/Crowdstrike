# AWS Cost Notifier - Architecture Documentation

## System Overview

The AWS Cost Notifier is a serverless, event-driven system that automatically retrieves daily AWS cost data and delivers formatted reports via email. The architecture follows AWS Well-Architected Framework principles with emphasis on reliability, security, and cost optimization.

## High-Level Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   EventBridge   │    │  Lambda Function │    │  Cost Explorer │
│   (Scheduler)   │───▶│  (Cost Notifier) │───▶│     (API)       │
│                 │    │                 │    │                 │
│ Cron: 8AM UTC   │    │ Runtime: 60s    │    │  Yesterday's    │
│ Daily Trigger   │    │ Memory: 512MB   │    │     Costs       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   DynamoDB      │    │  Email Formatter │    │      SES        │
│  (Tracking)     │◀──▶│   (HTML/Text)   │───▶│   (Email)       │
│                 │    │                 │    │                 │
│ Idempotency     │    │ Top 10 Services │    │ admin@company   │
│ Prevention      │    │ Cost Summary    │    │     .com        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   CloudWatch    │
                       │  (Monitoring)   │
                       │                 │
                       │ Logs + Alarms   │
                       │ + Dashboard     │
                       └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │      SNS        │
                       │   (Alerts)      │
                       │                 │
                       │ Email Alerts    │
                       │ for Failures    │
                       └─────────────────┘
```

## Component Architecture

### Core Components

#### 1. EventBridge (Scheduler)
- **Purpose**: Daily execution trigger
- **Schedule**: `cron(0 8 * * ? *)` - 8 AM UTC
- **State**: ENABLED by default
- **Input Transformation**: Passes timestamp and trigger type to Lambda

#### 2. Lambda Function
- **Runtime**: Python 3.11
- **Memory**: 512 MB
- **Timeout**: 60 seconds
- **Concurrency**: Default (no reserved concurrency needed)
- **Environment Variables**:
  - `ADMIN_EMAIL`: Cost report recipient
  - `SENDER_EMAIL`: SES sender address
  - `SES_REGION`: SES service region
  - `LOG_LEVEL`: Logging verbosity
  - `TRACKING_TABLE`: DynamoDB table name

#### 3. AWS Cost Explorer
- **Region**: us-east-1 (required)
- **API**: `get_cost_and_usage`
- **Time Period**: Previous day (T-1)
- **Granularity**: DAILY
- **Metrics**: BlendedCost
- **Grouping**: By SERVICE

#### 4. DynamoDB Table
- **Billing Mode**: PAY_PER_REQUEST
- **Primary Key**: `report_date` (String)
- **Purpose**: Idempotency tracking
- **Attributes**:
  - `report_date`: Date string (YYYY-MM-DD)
  - `sent_timestamp`: ISO timestamp
  - `status`: "sent"
  - `email_message_id`: SES message ID

#### 5. Amazon SES
- **Purpose**: Email delivery
- **Identities**: Sender and recipient email verification required
- **Regions**: Configurable (typically us-east-1)
- **Format**: HTML + Text multipart messages

### Monitoring Components

#### 6. CloudWatch Logs
- **Log Group**: `/aws/lambda/{function_name}`
- **Retention**: 30 days (configurable)
- **Structure**: JSON structured logging
- **Purpose**: Debugging and operational insights

#### 7. CloudWatch Alarms
- **Lambda Errors**: Triggers on any function failure
- **Duration SLO**: Alerts when execution > 30 seconds
- **Timeout Warning**: Early warning at 55 seconds
- **Missing Execution**: Detects if function doesn't run in 25 hours
- **Email Bounces**: SES delivery failure monitoring

#### 8. CloudWatch Dashboard
- **Widgets**: Lambda metrics + log insights
- **Metrics**: Invocations, Errors, Duration
- **SLO Visualization**: 30-second performance line
- **Log Query**: Recent ERROR entries

#### 9. SNS Topic
- **Purpose**: Alert notifications
- **Subscription**: Email to operations team
- **Trigger**: CloudWatch alarm state changes
- **Policy**: Allows CloudWatch to publish messages

## Data Flow

### 1. Scheduled Execution Flow

```
EventBridge Rule (8 AM UTC)
    │
    ▼
Lambda Function Invocation
    │
    ▼
Check DynamoDB for Today's Record
    │
    ├─ Record Exists ──▶ Return "Already Sent" ──▶ Exit
    │
    └─ No Record
        │
        ▼
    Cost Explorer API Call (with retry)
        │
        ▼
    Format Email Content (HTML + Text)
        │
        ▼
    Send Email via SES (with retry)
        │
        ▼
    Record Success in DynamoDB
        │
        ▼
    Return Success Response
```

### 2. Error Handling Flow

```
Exception Occurs in Lambda
    │
    ▼
Log Error to CloudWatch Logs
    │
    ▼
Re-raise Exception (triggers CloudWatch metric)
    │
    ▼
CloudWatch Alarm Evaluates Error Metric
    │
    ▼
Alarm State Change (OK → ALARM)
    │
    ▼
SNS Topic Receives Alarm Notification
    │
    ▼
Email Alert Sent to Operations Team
```

## Security Architecture

### Identity and Access Management

#### Lambda Execution Role
- **Principle of Least Privilege**: Only required permissions
- **CloudWatch Logs**: Write to own log group only
- **Cost Explorer**: Read-only access (`ce:GetCostAndUsage`)
- **SES**: Send from verified identities only
- **DynamoDB**: Read/write to tracking table only
- **X-Ray**: Basic tracing permissions

#### Resource-Based Policies
- **Lambda Permission**: EventBridge can invoke function
- **SNS Topic Policy**: CloudWatch can publish messages
- **Source ARN Restrictions**: Prevent cross-account access

### Network Security
- **VPC**: Not required (all services are AWS managed)
- **Internet Access**: Lambda needs internet for AWS API calls
- **Encryption**: All AWS services use encryption in transit and at rest

### Data Privacy
- **Email Content**: Processed in-memory, not persisted
- **Tracking Data**: Stored in customer-owned DynamoDB table

## Reliability and Resilience

### Error Handling Strategy

#### Retry Logic
- **Exponential Backoff**: 1s, 2s, 4s delays
- **Retryable Errors**: Throttling, rate limits, temporary failures
- **Max Attempts**: 3 per API call
- **Circuit Breaking**: Fail fast on non-retryable errors

#### Idempotency
- **DynamoDB Tracking**: Prevents duplicate email sends
- **Date-Based Keys**: One record per day
- **Graceful Degradation**: Tracking failures don't block emails

### Monitoring and Alerting

#### Service Level Objectives (SLO)
- **Availability**: 99.5% success rate
- **Performance**: 95% of executions under 30 seconds
- **Reliability**: Daily execution with <25 hour detection window

#### Alert Thresholds
- **Error Rate**: Any error triggers immediate alert
- **Performance**: 30-second SLO violation warning
- **Availability**: Missing execution after 25 hours

### Disaster Recovery
- **Infrastructure as Code**: Full environment recreation via Terraform
- **Stateless Function**: No persistent state in Lambda
- **Minimal State**: Only DynamoDB tracking data
- **Multi-AZ**: All AWS services are inherently multi-AZ

## Performance Architecture

### Scalability
- **Lambda Concurrency**: Single daily execution, no scaling needed
- **DynamoDB**: On-demand scaling handles minimal load
- **SES**: Regional service with high throughput capacity

### Optimization
- **Memory Allocation**: 512 MB balances cost and performance
- **Code Efficiency**: Minimal dependencies, optimized data processing
- **API Efficiency**: Single Cost Explorer call per execution

### Cost Optimization
- **Serverless**: Pay-per-use model
- **Right-sizing**: Appropriate memory/timeout settings
- **Minimal Storage**: DynamoDB on-demand, limited log retention

## Deployment Architecture

### Infrastructure as Code
- **Terraform Modules**: Separated by concern (main, monitoring)
- **State Management**: Remote state recommended for team environments
- **Environment Isolation**: Variable-driven configuration

### CI/CD Integration
- **Source Code**: Lambda function in `src/` directory
- **Packaging**: Terraform manages ZIP creation and deployment
- **Versioning**: Lambda version management via Terraform

### Configuration Management
- **Environment Variables**: Runtime configuration
- **Terraform Variables**: Infrastructure parameters
- **Secrets**: SES email addresses (not sensitive, stored in variables)

## Operational Architecture

### Logging Strategy
- **Structured Logging**: JSON format for machine parsing
- **Log Levels**: Configurable via environment variable
- **Retention**: 30-day default with configurable retention
- **Analysis**: CloudWatch Logs Insights for querying

### Monitoring Strategy
- **Built-in Metrics**: Lambda standard metrics (Invocations, Errors, Duration)
- **Custom Logs**: Business logic events for troubleshooting
- **Dashboard**: Operational view with key metrics and recent errors
- **Alerting**: Multi-channel notifications for different severity levels

### Maintenance Windows
- **No Downtime Required**: Serverless architecture
- **Update Strategy**: Blue/green deployment via Terraform
- **Testing**: Manual invocation capability for validation

## Integration Points

### External Dependencies
- **AWS Cost Explorer**: Primary data source
- **Amazon SES**: Email delivery service
- **AWS SDK**: Boto3 for service integration

### Internal Dependencies
- **IAM**: Permission management
- **EventBridge**: Scheduling service
- **CloudWatch**: Monitoring and logging
- **DynamoDB**: State persistence

### Extension Points
- **Additional Schedules**: Multiple EventBridge rules
- **Custom Metrics**: CloudWatch custom metrics integration
- **Additional Notifications**: Slack, Microsoft Teams via SNS
- **Cost Analysis**: Enhanced reporting with additional Cost Explorer dimensions

This architecture provides a robust, scalable, and maintainable solution for automated AWS cost reporting while adhering to AWS best practices for serverless applications.