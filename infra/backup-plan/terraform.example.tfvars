# Copy to terraform.tfvars (git-ignored) and fill in. Terraform reads it automatically.
# account_id is set by `make aws-backup-plan` from KESSAI_ACCOUNT_ID.

# Output backup_vault_arn of infra/backup-account.
backup_vault_arn = "arn:aws:backup:ap-northeast-3:210987654321:backup-vault:kessai-osaka"

# Optional overrides
# region              = "ap-northeast-1"
# copy_retention_days = 3
# eks_schedule        = "cron(0 9 * * ? *)"
