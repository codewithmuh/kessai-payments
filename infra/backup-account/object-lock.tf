# WORM storage for files that must survive a compromised workload account, such as daily ledger exports:
# S3 Object Lock in compliance mode. Every object version is locked for object_lock_retention_days; until
# then nobody, the root user included, can delete or overwrite it. Writers in the workload account
# (object_lock_writer_arns) may only add objects.
#
# 1-day retention keeps a portfolio removable: after a day the lifecycle rules below clear the bucket, and
# an empty bucket can be deleted.

# AWS-0089: Access logs need a second bucket; writes come only from object_lock_writer_arns and appear in CloudTrail.
#trivy:ignore:AWS-0089
resource "aws_s3_bucket" "object_lock" {
  #checkov:skip=CKV_AWS_18:Access logs need a second bucket; writes come only from the roles in object_lock_writer_arns and appear in CloudTrail.
  #checkov:skip=CKV_AWS_144:This bucket is itself the off-Region copy (Osaka); copying it back to Tokyo would undo the separation.
  #checkov:skip=CKV2_AWS_62:Nothing consumes bucket event notifications.
  bucket = "kessai-object-lock-${var.backup_account_id}"

  # Can only be turned on when the bucket is created. Also turns on versioning.
  object_lock_enabled = true
  force_destroy       = false
}

resource "aws_s3_bucket_object_lock_configuration" "object_lock" {
  bucket = aws_s3_bucket.object_lock.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.object_lock_retention_days
    }
  }
}

resource "aws_s3_bucket_versioning" "object_lock" {
  bucket = aws_s3_bucket.object_lock.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "object_lock" {
  bucket = aws_s3_bucket.object_lock.id

  # No ACLs: objects written by the workload account belong to this account.
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "object_lock" {
  bucket = aws_s3_bucket.object_lock.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "object_lock" {
  bucket = aws_s3_bucket.object_lock.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.backup.arn
    }
    # One data key per bucket for a while instead of one KMS call per object.
    bucket_key_enabled = true
  }
}

# Lifecycle rules cannot remove a locked version early; they act once its retention has ended.
resource "aws_s3_bucket_lifecycle_configuration" "object_lock" {
  bucket = aws_s3_bucket.object_lock.id

  rule {
    id     = "expire-after-retention"
    status = "Enabled"

    filter {}

    # The current version becomes noncurrent a day after its lock ends...
    expiration {
      days = var.object_lock_retention_days + 1
    }

    # ...and is deleted a day later.
    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  rule {
    id     = "remove-expired-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }

  depends_on = [aws_s3_bucket_versioning.object_lock]
}

data "aws_iam_policy_document" "object_lock_bucket" {
  # Requests without TLS are refused, whoever makes them.
  statement {
    sid     = "TlsOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.object_lock.arn,
      "${aws_s3_bucket.object_lock.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Writers from the workload account may add objects, nothing else: no reads, deletes or lock changes.
  dynamic "statement" {
    for_each = length(var.object_lock_writer_arns) > 0 ? [1] : []

    content {
      sid       = "WorkloadWritersAddOnly"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.object_lock.arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.object_lock_writer_arns
      }
    }
  }
}

resource "aws_s3_bucket_policy" "object_lock" {
  bucket = aws_s3_bucket.object_lock.id
  policy = data.aws_iam_policy_document.object_lock_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.object_lock]
}
