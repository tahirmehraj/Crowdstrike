# Variables for AWS Cost Notifier Lambda Infrastructure
# ===================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"  # Required for Cost Explorer API
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "aws-cost-notifier"
}

variable "admin_email" {
  description = "Email address to receive cost notifications (admin@company.com as per requirements)"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Admin email must be a valid email address format."
  }
}

variable "sender_email" {
  description = "Email address used as sender for cost notifications (must be verified in SES)"
  type        = string
  default     = "noreply@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sender_email))
    error_message = "Sender email must be a valid email address format."
  }
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alerts (can be same as admin_email)"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address format."
  }
}

variable "ses_region" {
  description = "AWS region for SES (should match aws_region unless specific requirements)"
  type        = string
  default     = "us-east-1"
}

variable "schedule_expression" {
  description = "Cron expression for daily execution (default: 8 AM UTC daily)"
  type        = string
  default     = "cron(0 8 * * ? *)"
  
  validation {
    condition     = can(regex("^cron\\(", var.schedule_expression))
    error_message = "Schedule expression must be a valid cron expression starting with 'cron('."
  }
}

variable "log_level" {
  description = "Log level for Lambda function (DEBUG, INFO, WARNING, ERROR, CRITICAL)"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

variable "use_ses" {
  description = "Whether to use SES for email delivery"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention value."
  }
}