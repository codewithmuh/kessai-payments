# This account's own key, for the vault and the Object Lock bucket. Copies are re-encrypted with it on
# arrival, so the workload account's key (and whoever controls it) no longer matters for them. A customer
# managed key, because Aurora snapshots cannot be copied across accounts into a vault that uses the AWS
# managed backup key.

resource "aws_kms_key" "backup" {
  description             = "Kessai backup copies (vault and Object Lock bucket) in the backup account"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.backup_key.json
}

resource "aws_kms_alias" "backup" {
  name          = "alias/kessai-backup"
  target_key_id = aws_kms_key.backup.key_id
}

# The default key policy, written out: this account's IAM policies decide who uses the key. The workload
# account gets nothing, except the Object Lock writers, which may encrypt new objects through S3 only.
data "aws_iam_policy_document" "backup_key" {
  #checkov:skip=CKV_AWS_109:Key policy: Resource "*" is this key only, and the root principal delegates to IAM policies.
  #checkov:skip=CKV_AWS_111:Key policy: Resource "*" is this key only, and the root principal delegates to IAM policies.
  #checkov:skip=CKV_AWS_356:Key policy: Resource "*" is this key only, and the root principal delegates to IAM policies.
  statement {
    sid       = "AccountIamPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.backup_account_id}:root"]
    }
  }

  # KMS checks that these roles exist when the policy is saved: create them in the workload account first.
  # Decrypt as well as GenerateDataKey, because S3 needs it for multipart uploads.
  dynamic "statement" {
    for_each = length(var.object_lock_writer_arns) > 0 ? [1] : []

    content {
      sid       = "ObjectLockWritersEncryptThroughS3"
      actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.object_lock_writer_arns
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${var.region}.amazonaws.com"]
      }
    }
  }
}
