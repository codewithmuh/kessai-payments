# Copy to terraform.tfvars (git-ignored) if you need overrides. Terraform reads it automatically.
# account_id is set by `make aws-fis` from KESSAI_ACCOUNT_ID. Every other value has a default.

# Optional overrides
# region                = "ap-northeast-1"
# impaired_az_id        = "apne1-az1"   # drill 4 in an AZ without the NAT gateway
# az_impairment_minutes = 10
# api_pod_selection     = "COUNT(1)"
