variable "account_id" {
  description = "The AWS account Kessai runs in (the workload account). The provider refuses every other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region of the state bucket, the money-data key and the platform."
  type        = string
  default     = "ap-northeast-1"
}

variable "github_repository" {
  description = "owner/name of the only GitHub repository whose workflows may assume the CI roles."
  type        = string
  default     = "codewithmuh/kessai-payments"
}

variable "github_environment" {
  description = "GitHub environment that may assume the apply role. Give it a required reviewer in the repo settings."
  type        = string
  default     = "aws-tokyo"
}

variable "monthly_budget_usd" {
  description = "Monthly AWS budget in USD. Alerts go out at 50 % and 80 % of actual spend, and 100 % forecast."
  type        = number
  default     = 100
}

variable "daily_budget_usd" {
  description = "Daily spend that triggers an alert. A session costs ~$5 and a day left running ~$14, so $10 catches a forgotten teardown (and fires on Osaka DR days, which cost ~$9-12)."
  type        = number
  default     = 10
}

variable "budget_alert_email" {
  description = "Where budget alerts are sent. Set it in terraform.tfvars (git-ignored), never in git."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be an email address."
  }
}

variable "backup_account_id" {
  description = "The separate backup account (infra/backup-account). When set, it may use the money-data key, which AWS Backup needs to copy Aurora snapshots into it. Leave null until that account exists."
  type        = string
  default     = null

  validation {
    condition     = var.backup_account_id == null || can(regex("^[0-9]{12}$", var.backup_account_id))
    error_message = "backup_account_id must be null or a 12-digit AWS account ID."
  }

  validation {
    condition     = var.backup_account_id != var.account_id
    error_message = "backup_account_id must be a different account: backups in the same account do not survive a compromised account."
  }
}
