variable "backup_account_id" {
  description = "The separate AWS account that holds the backup copies. The provider refuses every other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.backup_account_id))
    error_message = "backup_account_id must be a 12-digit AWS account ID."
  }
}

variable "workload_account_id" {
  description = "The account Kessai runs in. It may copy backups INTO this account's vault, and nothing else."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.workload_account_id))
    error_message = "workload_account_id must be a 12-digit AWS account ID."
  }

  validation {
    condition     = var.workload_account_id != var.backup_account_id
    error_message = "The backup account must be a different account from the workload account."
  }
}

variable "region" {
  description = "Region of the backup copies. Osaka: a different geography from Tokyo, inside Japan."
  type        = string
  default     = "ap-northeast-3"
}

################################################################################
# AWS Backup vault and Vault Lock
################################################################################

variable "vault_min_retention_days" {
  description = "Vault Lock minimum: every copy must be kept at least this long, and nobody can delete it sooner. 1 day, the shortest AWS allows, so a portfolio can be torn down."
  type        = number
  default     = 1

  validation {
    condition     = var.vault_min_retention_days >= 1
    error_message = "AWS Backup Vault Lock needs at least 1 day."
  }
}

variable "vault_max_retention_days" {
  description = "Vault Lock maximum: a copy with a longer retention is refused. Caps what a locked vault can cost."
  type        = number
  default     = 7

  validation {
    condition     = var.vault_max_retention_days >= var.vault_min_retention_days
    error_message = "vault_max_retention_days must not be smaller than vault_min_retention_days."
  }
}

variable "vault_lock_changeable_for_days" {
  description = "null = governance mode (an admin with IAM permissions can remove the lock). A number (at least 3) = compliance mode: after that many days the lock can never be removed, by anyone, AWS included."
  type        = number
  default     = null

  validation {
    condition     = var.vault_lock_changeable_for_days == null || try(var.vault_lock_changeable_for_days >= 3, false)
    error_message = "Compliance mode needs a grace time of at least 3 days (72 hours)."
  }
}

################################################################################
# S3 Object Lock bucket
################################################################################

variable "object_lock_retention_days" {
  description = "Every object version is locked in compliance mode for this many days: not even the root user can delete or overwrite it sooner."
  type        = number
  default     = 1
}

variable "object_lock_writer_arns" {
  description = "IAM roles in the workload account that may add objects (never delete them), e.g. a ledger export job. Empty: nobody outside this account."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.object_lock_writer_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/", arn))])
    error_message = "Each writer must be an IAM role ARN."
  }
}
