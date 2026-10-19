terraform {
  # 1.10+ for S3-native state locking (use_lockfile); no DynamoDB table needed.
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }

  # State lives in a bucket in the BACKUP account, made by the same script as the workload account's
  # (infra/Makefile: backup-account-bootstrap). Nothing in the workload account, not even this state,
  # can change the backup account.
  #   terraform init -backend-config=bucket=kessai-tfstate-<backup-account-id> -backend-config=region=<backup-region>
  backend "s3" {
    key          = "backup-account/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
