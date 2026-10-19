# Applied with the backup account's own credentials: AWS_PROFILE set to its profile (infra/README.md).
# allowed_account_ids makes a mix-up with the workload profile fail before anything is touched.
provider "aws" {
  region = var.region

  allowed_account_ids = [var.backup_account_id]

  default_tags {
    tags = {
      Project    = "kessai"
      Stack      = "backup-account"
      ManagedBy  = "terraform"
      Repository = "codewithmuh/kessai-payments"
    }
  }
}
