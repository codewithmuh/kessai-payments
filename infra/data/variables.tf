variable "account_id" {
  description = "The AWS account Kessai runs in (the workload account). The provider refuses every other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region. Must match infra/platform: this stack uses its VPC and cluster."
  type        = string
  default     = "ap-northeast-1"
}

variable "name" {
  description = "Name of the platform (VPC, cluster) this stack attaches to, and prefix of everything it creates."
  type        = string
  default     = "kessai"

  validation {
    condition     = var.name == "kessai" || startswith(var.name, "kessai-")
    error_message = "name must be \"kessai\" or start with \"kessai-\", or the CI apply role cannot create its IAM roles."
  }
}

variable "environment" {
  description = "Environment tag."
  type        = string
  default     = "dev"
}

variable "app_namespace" {
  description = "Kubernetes namespace of the Kessai workloads; their Pod Identity associations are made for it."
  type        = string
  default     = "kessai"
}

################################################################################
# Aurora
################################################################################

variable "db_engine_version" {
  description = "Aurora PostgreSQL version. 17.7 is the long-term-support minor (standard support to 2030-02-28), so it never moves under a Global Database, whose two Regions must run the same minor."
  type        = string
  default     = "17.7"
}

variable "db_instance_class" {
  description = "Instance class of the writer and the reader. db.t4g.medium (~$0.113/h each in Tokyo) for normal sessions; an r-class on DR days (Global Database requires memory-optimized classes)."
  type        = string
  default     = "db.t4g.medium"
}

variable "db_instance_az_ids" {
  description = "Zone IDs of the two DB instances, one each. Whichever is created first becomes the writer; a failover swaps the roles."
  type        = list(string)
  default     = ["apne1-az4", "apne1-az1"]

  validation {
    condition     = length(var.db_instance_az_ids) == 2 && length(distinct(var.db_instance_az_ids)) == 2
    error_message = "Give two different zone IDs: the writer and the reader must not share an AZ."
  }
}

variable "db_backup_retention_days" {
  description = "Days of automated backups, which is also the point-in-time-restore window (drill 6)."
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_days >= 1 && var.db_backup_retention_days <= 35
    error_message = "Aurora keeps between 1 and 35 days of backups."
  }
}

variable "deletion_protection" {
  description = "Stops anyone, Terraform included, from deleting the cluster. `make aws-down` sets it to false in an explicit apply first."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Delete the cluster without a final snapshot. Keep false: the snapshot is the last copy of the session's ledger."
  type        = bool
  default     = false
}

variable "enable_global_database" {
  description = "Turn the cluster into the primary of an Aurora Global Database, so an Osaka secondary can join (DR days only). Needs an r-class db_instance_class."
  type        = bool
  default     = false

  # Global Database runs on memory-optimized classes only (db.r5 and later, or db.x2g), never on t-class.
  validation {
    condition     = !var.enable_global_database || can(regex("^db\\.(r[5-9]|x2)", var.db_instance_class))
    error_message = "Aurora Global Database needs a memory-optimized instance class (db.r5 or later, e.g. db.r7g.large). Set db_instance_class too."
  }
}

variable "log_retention_days" {
  description = "Retention of the PostgreSQL log in CloudWatch. Short on purpose: the cluster lives for one session."
  type        = number
  default     = 7
}

################################################################################
# Webhook queue
################################################################################

variable "webhook_visibility_timeout_seconds" {
  description = "How long a webhook event stays hidden after a sender picks it up. Longer than one delivery attempt (HTTP timeout plus signing)."
  type        = number
  default     = 60
}

variable "webhook_max_receive_count" {
  description = "Delivery attempts before an event moves to the dead-letter queue (drill 2: merchant down for 30 minutes)."
  type        = number
  default     = 5
}
