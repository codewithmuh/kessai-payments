terraform {
  # 1.10+ for S3-native state locking (use_lockfile); no DynamoDB table needed.
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }

  # Bucket and region are passed at init time (infra/Makefile), so no account ID or region is committed:
  #   terraform init -backend-config=bucket=kessai-tfstate-<account-id> -backend-config=region=<region>
  backend "s3" {
    key          = "platform/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
