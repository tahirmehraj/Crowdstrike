# lambda_function.py
"""
AWS Cost Notifier Lambda - Simplified Version
Queries AWS Cost Explorer and sends daily cost summary emails via SES.
"""

import boto3
import json
import time
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, Any
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))


class CostNotifierError(Exception):
    """Custom exception for cost notifier failures"""
    pass


def already_sent_today() -> bool:
    """Check if cost report was already sent for today."""
    try:
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ.get('TRACKING_TABLE', 'aws-cost-notifier-tracking'))

        today = (datetime.utcnow() - timedelta(days=1)).strftime('%Y-%m-%d')
        response = table.get_item(Key={'report_date': today})

        if 'Item' in response:
            logger.info(f"Report already sent for {today}")
            return True
        return False

    except Exception as e:
        logger.error(f"Error checking tracking table: {e}")
        return False  # On error, assume not sent


def mark_as_sent(message_id: str) -> None:
    """Mark today's report as sent."""
    try:
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ.get('TRACKING_TABLE', 'aws-cost-notifier-tracking'))

        today = (datetime.utcnow() - timedelta(days=1)).strftime('%Y-%m-%d')
        table.put_item(Item={
            'report_date': today,
            'sent_timestamp': datetime.utcnow().isoformat(),
            'status': 'sent',
            'email_message_id': message_id
        })
        logger.info(f"Marked {today} as sent")

    except Exception as e:
        logger.error(f"Error updating tracking table: {e}")


def get_cost_data() -> Dict[str, Any]:
    """Retrieve yesterday's cost data from Cost Explorer with retry."""
    max_retries = 3

    # Get yesterday's date
    yesterday = datetime.utcnow().date() - timedelta(days=1)
    today = datetime.utcnow().date()

    for attempt in range(max_retries):
        try:
            logger.info(f"Getting cost data for {yesterday} (attempt {attempt + 1})")

            cost_explorer = boto3.client('ce', region_name='us-east-1')
            response = cost_explorer.get_cost_and_usage(
                TimePeriod={
                    'Start': yesterday.strftime('%Y-%m-%d'),
                    'End': today.strftime('%Y-%m-%d')
                },
                Granularity='DAILY',
                Metrics=['BlendedCost'],
                GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}]
            )

            logger.info("Successfully retrieved cost data")
            return response

        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code in ['Throttling', 'RequestLimitExceeded'] and attempt < max_retries - 1:
                wait_time = 2 ** attempt
                logger.warning(f"Cost Explorer throttled, waiting {wait_time}s")
                time.sleep(wait_time)
                continue
            else:
                raise CostNotifierError(f"Cost Explorer API failed: {error_code}")

        except Exception as e:
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)
                continue
            raise CostNotifierError(f"Failed to get cost data: {e}")

    raise CostNotifierError("Exhausted all retry attempts")


def format_email(cost_data: Dict[str, Any]) -> Dict[str, str]:
    """Format cost data into email content."""
    if not cost_data.get('ResultsByTime'):
        return {
            'subject': 'AWS Daily Cost Report - No Data',
            'text': 'No cost data available for yesterday.',
            'html': '<p>No cost data available for yesterday.</p>'
        }

    result = cost_data['ResultsByTime'][0]
    date_str = result['TimePeriod']['Start']
    total_cost = float(result['Total']['BlendedCost']['Amount'])

    # Sort services by cost (top 10)
    services = sorted(
        result['Groups'],
        key=lambda x: float(x['Metrics']['BlendedCost']['Amount']),
        reverse=True
    )[:10]

    # Create text version
    text_content = f"""AWS Daily Cost Report - {date_str}

Total Cost: ${total_cost:.2f}

Top Services:
"""
    for service in services:
        service_name = service['Keys'][0]
        service_cost = float(service['Metrics']['BlendedCost']['Amount'])
        if service_cost >= 0.01:  # Only show services > 1 cent
            text_content += f"  {service_name}: ${service_cost:.2f}\n"

    # Create HTML version
    html_content = f"""
    <html>
    <body style="font-family: Arial, sans-serif; margin: 20px;">
        <h2>AWS Daily Cost Report - {date_str}</h2>

        <div style="background-color: #e8f4fd; padding: 15px; border-radius: 5px; margin: 20px 0;">
            <h3>Total Cost: ${total_cost:.2f}</h3>
        </div>

        <h3>Top Services:</h3>
        <table style="border-collapse: collapse; width: 100%;">
            <tr style="background-color: #f2f2f2;">
                <th style="border: 1px solid #ddd; padding: 8px; text-align: left;">Service</th>
                <th style="border: 1px solid #ddd; padding: 8px; text-align: left;">Cost</th>
            </tr>
    """

    for service in services:
        service_name = service['Keys'][0]
        service_cost = float(service['Metrics']['BlendedCost']['Amount'])
        if service_cost >= 0.01:
            html_content += f"""
            <tr>
                <td style="border: 1px solid #ddd; padding: 8px;">{service_name}</td>
                <td style="border: 1px solid #ddd; padding: 8px;">${service_cost:.2f}</td>
            </tr>
            """

    html_content += """
        </table>
        <p style="margin-top: 30px; font-size: 12px; color: #666;">
            Generated automatically by AWS Cost Notifier
        </p>
    </body>
    </html>
    """

    return {
        'subject': f'AWS Daily Cost Report - ${total_cost:.2f}',
        'text': text_content,
        'html': html_content
    }


def send_email(email_content: Dict[str, str]) -> Dict[str, Any]:
    """Send email via SES with retry."""
    max_retries = 3

    admin_email = os.environ.get('ADMIN_EMAIL', 'admin@company.com')
    sender_email = os.environ.get('SENDER_EMAIL', 'noreply@company.com')
    ses_region = os.environ.get('SES_REGION', 'us-east-1')

    for attempt in range(max_retries):
        try:
            logger.info(f"Sending email (attempt {attempt + 1})")

            ses = boto3.client('ses', region_name=ses_region)

            response = ses.send_email(
                Source=sender_email,
                Destination={'ToAddresses': [admin_email]},
                Message={
                    'Subject': {'Data': email_content['subject']},
                    'Body': {
                        'Html': {'Data': email_content['html']},
                        'Text': {'Data': email_content['text']}
                    }
                }
            )

            logger.info(f"Email sent successfully: {response.get('MessageId')}")
            return response

        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code in ['Throttling', 'SendingPausedException'] and attempt < max_retries - 1:
                wait_time = 2 ** attempt
                logger.warning(f"SES throttled, waiting {wait_time}s")
                time.sleep(wait_time)
                continue
            else:
                raise CostNotifierError(f"SES email failed: {error_code}")

        except Exception as e:
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)
                continue
            raise CostNotifierError(f"Failed to send email: {e}")

    raise CostNotifierError("Exhausted all email retry attempts")


def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Main Lambda handler."""
    start_time = time.time()
    request_id = getattr(context, 'aws_request_id', 'unknown')

    logger.info(f"Starting cost notifier execution - Request ID: {request_id}")

    try:
        # Check if already sent today
        if already_sent_today():
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Cost report already sent today',
                    'duplicate_prevented': True
                })
            }

        # Get cost data
        cost_data = get_cost_data()

        # Format email
        email_content = format_email(cost_data)

        # Send email
        email_result = send_email(email_content)

        # Mark as sent
        mark_as_sent(email_result.get('MessageId', ''))

        # Calculate execution time
        execution_time = time.time() - start_time

        # Log SLO compliance
        if execution_time > 30:
            logger.warning(f"Execution time {execution_time:.1f}s exceeded 30s SLO")

        logger.info(f"Cost notification completed successfully in {execution_time:.1f}s")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost notification sent successfully',
                'execution_time': round(execution_time, 2),
                'email_message_id': email_result.get('MessageId')
            })
        }

    except Exception as e:
        execution_time = time.time() - start_time
        logger.error(f"Cost notifier failed after {execution_time:.1f}s: {str(e)}")
        raise  # Re-raise to trigger CloudWatch alarms