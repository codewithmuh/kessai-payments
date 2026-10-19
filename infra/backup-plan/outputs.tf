output "tokyo_vault_name" {
  description = "Local vault in the workload account (recovery points kept local_retention_days)."
  value       = aws_backup_vault.tokyo.name
}

output "backup_role_arn" {
  description = "Role AWS Backup uses; pass it to on-demand backup and restore jobs."
  value       = aws_iam_role.backup.arn
}

output "backup_eks_now" {
  description = "Drill 7: an on-demand EKS backup, copied to the backup account like the scheduled ones."
  value       = "aws backup start-backup-job --region ${var.region} --backup-vault-name ${aws_backup_vault.tokyo.name} --resource-arn ${local.eks_cluster_arn} --iam-role-arn ${aws_iam_role.backup.arn}"
}

output "backup_aurora_now" {
  description = "An on-demand Aurora snapshot (not copied: on-demand jobs skip the plan's copy rule; copy with aws backup start-copy-job)."
  value       = "aws backup start-backup-job --region ${var.region} --backup-vault-name ${aws_backup_vault.tokyo.name} --resource-arn ${local.aurora_cluster_arn} --iam-role-arn ${aws_iam_role.backup.arn}"
}
