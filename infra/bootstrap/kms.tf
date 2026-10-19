# The money-data key: one customer managed key for Aurora storage, the database secret, the settlement
# files and the local AWS Backup vault. It lives in this stack, which is applied once and never destroyed
# by a session, because a key that died with the session would make every snapshot and backup taken with
# it unreadable. About $1 a month.
#
# Multi-Region: Osaka can later get a replica (aws_kms_replica_key) with the same key ID and key
# material, for the Aurora Global Database secondary and the Secrets Manager replicas on DR days.

resource "aws_kms_key" "data" {
  description             = "Kessai money data: Aurora, database secret, settlement files, backups"
  multi_region            = true
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.data_key.json
}

resource "aws_kms_alias" "data" {
  # infra/platform, infra/data and infra/backup-plan find the key by this name.
  name          = "alias/kessai-data"
  target_key_id = aws_kms_key.data.key_id
}

# The default key policy, written out, plus the backup account. In a key policy, Resource "*" means this key.
data "aws_iam_policy_document" "data_key" {
  #checkov:skip=CKV_AWS_109:Key policy: Resource "*" is this key only, and the root principal delegates to IAM policies.
  #checkov:skip=CKV_AWS_111:Key policy: Resource "*" is this key only, and the root principal delegates to IAM policies.
  #checkov:skip=CKV_AWS_356:Key policy: Resource "*" is this key only, and the root principal delegates to IAM policies.

  # The account's IAM policies decide who may use the key (Pod Identity roles, the CI apply role, admins).
  statement {
    sid       = "AccountIamPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
  }

  # Aurora snapshots stay encrypted with this key, so AWS Backup in the backup account must be able to
  # read them to copy them into its own vault, where they are re-encrypted with that vault's key.
  # Read and grant only: the backup account can never change or delete this key.
  dynamic "statement" {
    for_each = var.backup_account_id == null ? [] : [var.backup_account_id]

    content {
      sid = "BackupAccountCopiesSnapshots"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = ["arn:aws:iam::${statement.value}:root"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.backup_account_id == null ? [] : [var.backup_account_id]

    content {
      sid       = "BackupAccountGrantsForAwsServices"
      actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = ["arn:aws:iam::${statement.value}:root"]
      }

      # Only grants that an AWS service (here AWS Backup and RDS) creates on the account's behalf.
      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }
}
