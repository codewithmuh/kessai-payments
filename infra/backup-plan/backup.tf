# AWS Backup in the workload account: back up Aurora and the EKS cluster in Tokyo, and copy every recovery
# point to the backup account's locked vault in Osaka (infra/backup-account), cross-account and
# cross-Region in one copy action. Both resource types support that (AWS Backup feature availability,
# checked 2026-10-19; AWS Backup for EKS is GA since 2025-11-10).
#
# A stack of its own, applied once like infra/bootstrap, because it must outlive every session: the Tokyo
# vault holds recovery points, and a vault cannot be deleted while it does. It selects the clusters by ARN,
# so the plan is harmless while they don't exist and picks them up when a session creates them.
#
#   Aurora  hourly snapshot; storage stays encrypted with the money-data key, which infra/bootstrap shares
#           with the backup account so it can copy them. Point-in-time restore (drill 6) comes from Aurora's
#           own backups, not from here: a copied continuous backup becomes a plain snapshot anyway.
#   EKS     daily; cluster state (manifests, add-ons, access entries...) and any EBS persistent volumes.
#           AWS Backup reaches the cluster through an access entry it creates itself (needs API auth mode).

locals {
  aurora_cluster_arn = "arn:aws:rds:${var.region}:${var.account_id}:cluster:${var.name}"
  eks_cluster_arn    = "arn:aws:eks:${var.region}:${var.account_id}:cluster/${var.name}"
}

# The money-data key from infra/bootstrap encrypts the Tokyo vault.
data "aws_kms_alias" "data" {
  name = "alias/kessai-data"
}

resource "aws_backup_vault" "tokyo" {
  name        = "${var.name}-tokyo"
  kms_key_arn = data.aws_kms_alias.data.target_key_arn

  # Recovery points expire after local_retention_days; Terraform never deletes them early.
  force_destroy = false
}

################################################################################
# The role AWS Backup uses to take, copy and restore backups
################################################################################

data "aws_iam_policy_document" "backup_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.name}-backup"
  description        = "AWS Backup: back up and restore Kessai's Aurora and EKS clusters, copy to the backup account"
  assume_role_policy = data.aws_iam_policy_document.backup_trust.json
}

# AWS's managed policies cover Aurora, EKS (cluster state, EBS and EFS volumes) and the cross-account
# copy permissions (backup:CopyFromBackupVault, backup:CopyIntoBackupVault).
resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

################################################################################
# Plans: one per resource type, because every rule of a plan applies to every resource it selects
################################################################################

resource "aws_backup_plan" "aurora" {
  name = "${var.name}-aurora"

  rule {
    rule_name         = "hourly-copy-to-backup-account"
    target_vault_name = aws_backup_vault.tokyo.name
    schedule          = var.aurora_schedule
    start_window      = 60  # minutes
    completion_window = 180 # minutes

    lifecycle {
      delete_after = var.local_retention_days
    }

    copy_action {
      destination_vault_arn = var.backup_vault_arn

      lifecycle {
        delete_after = var.copy_retention_days
      }
    }
  }
}

resource "aws_backup_selection" "aurora" {
  name         = "${var.name}-aurora"
  plan_id      = aws_backup_plan.aurora.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [local.aurora_cluster_arn]
}

resource "aws_backup_plan" "eks" {
  name = "${var.name}-eks"

  rule {
    rule_name         = "daily-copy-to-backup-account"
    target_vault_name = aws_backup_vault.tokyo.name
    schedule          = var.eks_schedule
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.local_retention_days
    }

    copy_action {
      destination_vault_arn = var.backup_vault_arn

      lifecycle {
        delete_after = var.copy_retention_days
      }
    }
  }
}

resource "aws_backup_selection" "eks" {
  name         = "${var.name}-eks"
  plan_id      = aws_backup_plan.eks.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [local.eks_cluster_arn]
}
