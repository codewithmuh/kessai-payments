# The role and bucket values go into GitHub repository variables (Settings → Secrets and variables → Actions).

output "plan_role_arn" {
  description = "GitHub variable AWS_PLAN_ROLE_ARN: the role the Terraform workflow assumes to plan pull requests."
  value       = aws_iam_role.github_plan.arn
}

output "apply_role_arn" {
  description = "GitHub variable AWS_APPLY_ROLE_ARN: the role the apply workflow assumes to create and destroy the per-session stacks."
  value       = aws_iam_role.github_apply.arn
}

output "state_bucket" {
  description = "GitHub variable TF_STATE_BUCKET: the S3 bucket that holds the Terraform state."
  value       = local.state_bucket
}

output "data_key_arn" {
  description = "Multi-Region KMS key for Kessai's money data (alias/kessai-data)."
  value       = aws_kms_key.data.arn
}
