# The last line of defence (drill 8, the ransomware drill): a vault in a different account and a
# different Region. AWS Backup in the workload account copies Aurora and EKS recovery points into it
# (infra/backup-plan). Whoever controls the workload account, even its root user, cannot reach them.
#
# Cross-account copies need AWS Organizations: both accounts in the same organization, and
# "cross-account backup" turned on once from the organization's management account (infra/README.md).

resource "aws_backup_vault" "this" {
  name        = "kessai-osaka"
  kms_key_arn = aws_kms_key.backup.arn

  # Terraform never deletes recovery points; Vault Lock would refuse anyway until their retention ends.
  force_destroy = false
}

# Vault Lock: every recovery point stays until its retention ends, whoever asks to delete it.
#
#   Governance mode (default, vault_lock_changeable_for_days = null): users with the right IAM permissions
#   in this account can still remove the lock. Protects against the workload account, not against an
#   admin of this one.
#
#   Compliance mode (vault_lock_changeable_for_days = 3 or more): during that grace time (at least 72 hours)
#   the lock can still be changed or removed. After it, the lock is permanent: nobody, not the root user and
#   not AWS, can remove it, shorten a retention or delete the vault while it holds recovery points. Choose it
#   only with retentions you are willing to pay for until they end. The 1-day minimum and 7-day maximum
#   below keep that small, and an emptied vault can still be deleted.
resource "aws_backup_vault_lock_configuration" "this" {
  backup_vault_name   = aws_backup_vault.this.name
  min_retention_days  = var.vault_min_retention_days
  max_retention_days  = var.vault_max_retention_days
  changeable_for_days = var.vault_lock_changeable_for_days
}

# The one thing the workload account may do here: copy recovery points in. In a vault access policy,
# Resource "*" means this vault.
data "aws_iam_policy_document" "vault_access" {
  #checkov:skip=CKV_AWS_111:Vault access policy: Resource "*" is this vault only.
  #checkov:skip=CKV_AWS_356:Vault access policy: Resource "*" is this vault only.
  statement {
    sid       = "WorkloadAccountCopiesIn"
    actions   = ["backup:CopyIntoBackupVault"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.workload_account_id}:root"]
    }
  }
}

resource "aws_backup_vault_policy" "this" {
  backup_vault_name = aws_backup_vault.this.name
  policy            = data.aws_iam_policy_document.vault_access.json
}
