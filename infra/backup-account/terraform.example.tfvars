# Copy to terraform.tfvars (git-ignored) and fill in. Terraform reads it automatically.
# backup_account_id is set by `make backup-account` from KESSAI_BACKUP_ACCOUNT_ID.

workload_account_id = "123456789012"

# Optional overrides
# region                   = "ap-northeast-3"
# vault_max_retention_days = 7
# object_lock_writer_arns  = ["arn:aws:iam::123456789012:role/kessai-ledger-export"]

# Compliance mode for the drill-8 recording. After 3 days the lock is permanent; read vault.tf first.
# vault_lock_changeable_for_days = 3
