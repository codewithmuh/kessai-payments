output "backup_vault_arn" {
  description = "Destination vault for the workload account's copies: infra/backup-plan variable backup_vault_arn."
  value       = aws_backup_vault.this.arn
}

output "vault_lock_mode" {
  description = "Governance or compliance, as configured."
  value       = var.vault_lock_changeable_for_days == null ? "governance" : "compliance (permanent after ${var.vault_lock_changeable_for_days} days)"
}

output "object_lock_bucket" {
  description = "S3 bucket with Object Lock in compliance mode."
  value       = aws_s3_bucket.object_lock.id
}
