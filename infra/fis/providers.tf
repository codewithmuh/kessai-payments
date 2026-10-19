provider "aws" {
  region = var.region

  # Refuse to touch any account except Kessai's, even if the shell is logged in to another one.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project     = var.name
      Environment = var.environment
      Stack       = "fis"
      ManagedBy   = "terraform"
      Repository  = "codewithmuh/kessai-payments"
    }
  }
}
