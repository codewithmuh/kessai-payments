variable "account_id" {
  description = "The AWS account Kessai runs in (the workload account). The provider refuses every other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "Region of the protected resources and of the local vault (Tokyo)."
  type        = string
  default     = "ap-northeast-1"
}

variable "name" {
  description = "Name of the EKS and Aurora clusters to back up (infra/platform, infra/data)."
  type        = string
  default     = "kessai"

  validation {
    condition     = var.name == "kessai" || startswith(var.name, "kessai-")
    error_message = "name must be \"kessai\" or start with \"kessai-\"."
  }
}

variable "backup_vault_arn" {
  description = "The backup account's vault in Osaka: output backup_vault_arn of infra/backup-account."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:backup:[a-z0-9-]+:[0-9]{12}:backup-vault:.+$", var.backup_vault_arn))
    error_message = "backup_vault_arn must look like arn:aws:backup:ap-northeast-3:210987654321:backup-vault:kessai-osaka."
  }

  validation {
    condition     = try(split(":", var.backup_vault_arn)[4], "") != var.account_id
    error_message = "The copy must go to a different account; a vault in the workload account does not survive a compromised workload account."
  }
}

variable "aurora_schedule" {
  description = "When AWS Backup snapshots Aurora (UTC cron). Hourly: the platform only exists during sessions, so a daily time would usually miss it."
  type        = string
  default     = "cron(0 * * * ? *)"
}

variable "eks_schedule" {
  description = "When AWS Backup backs up the EKS cluster (UTC cron). Once a day (09:00 UTC = 18:00 JST): EKS backups cost about $0.12 per namespace each time. Drill 7 takes an on-demand backup."
  type        = string
  default     = "cron(0 9 * * ? *)"
}

variable "local_retention_days" {
  description = "Days the recovery points stay in the Tokyo vault. 1, the minimum: the long-lived copy is the one in the backup account."
  type        = number
  default     = 1
}

variable "copy_retention_days" {
  description = "Days the copies stay in the backup account. Must lie within that vault's lock range (1-7 days by default)."
  type        = number
  default     = 3

  validation {
    condition     = var.copy_retention_days >= 1
    error_message = "AWS Backup keeps a recovery point at least 1 day."
  }
}
