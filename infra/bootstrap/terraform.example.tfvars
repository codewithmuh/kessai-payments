# Copy to terraform.tfvars (git-ignored) and fill in. Terraform reads it automatically.
# account_id is set by `make aws-bootstrap` from KESSAI_ACCOUNT_ID.

budget_alert_email = "you@example.com"

# Set once the backup account exists (infra/backup-account), then run `make aws-bootstrap` again.
# backup_account_id = "210987654321"

# Optional overrides
# region             = "ap-northeast-1"
# monthly_budget_usd = 100
# daily_budget_usd   = 10
