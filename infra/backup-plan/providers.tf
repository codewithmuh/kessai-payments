provider "aws" {
  region = var.region

  # Refuse to touch any account except Kessai's workload account.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project    = var.name
      Stack      = "backup-plan"
      ManagedBy  = "terraform"
      Repository = "codewithmuh/kessai-payments"
    }
  }
}
