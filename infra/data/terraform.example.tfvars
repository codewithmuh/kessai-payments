# Copy to terraform.tfvars (git-ignored) if you need overrides. Terraform reads it automatically.
# account_id is set by `make aws-up` from KESSAI_ACCOUNT_ID. Every other value has a default.

# Optional overrides
# region            = "ap-northeast-1"
# db_instance_class = "db.t4g.medium"

# DR days only (Phase 3): both lines together, the global database needs an r-class instance.
# enable_global_database = true
# db_instance_class      = "db.r7g.large"
