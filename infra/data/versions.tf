terraform {
  # 1.11+ for write-only arguments (master_password_wo): the DR-day database password never lands in state.
  required_version = ">= 1.11, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
    # 3.7+ for the ephemeral random_password in global-database.tf.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  #   terraform init -backend-config=bucket=kessai-tfstate-<account-id> -backend-config=region=<region>
  backend "s3" {
    key          = "data/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
