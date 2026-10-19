# Settlement files: mock-bank writes one file a day, the way a real bank sends one, and the daily
# reconciliation CronJob checks the ledger against it (money rule R7). Encrypted with the money-data key,
# because in real life these are bank statements.
#
# The bucket lives and dies with the session (force_destroy): its files are test data that mock-bank can
# write again. Long-lived, immutable copies belong in the backup account (infra/backup-account).

# AWS-0089: Access logs need a second bucket; only two Pod Identity roles touch this one, and their KMS use is in CloudTrail.
#trivy:ignore:AWS-0089
resource "aws_s3_bucket" "settlements" {
  #checkov:skip=CKV_AWS_18:Access logs need a second bucket; only two Pod Identity roles touch this one, and their KMS use is in CloudTrail.
  #checkov:skip=CKV_AWS_144:Cross-region copies are not needed for test data that mock-bank can regenerate; the backup account holds the long-lived copies.
  #checkov:skip=CKV2_AWS_62:Nothing consumes bucket event notifications; reconciliation runs on a schedule.
  bucket = "${var.name}-settlements-${var.account_id}"

  # Session test data: `make aws-down` deletes it with every object version.
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "settlements" {
  bucket = aws_s3_bucket.settlements.id

  # No ACLs: access is decided by IAM and the bucket policy only.
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "settlements" {
  bucket = aws_s3_bucket.settlements.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# An overwritten or deleted file stays recoverable as a noncurrent version (expired below after 7 days).
resource "aws_s3_bucket_versioning" "settlements" {
  bucket = aws_s3_bucket.settlements.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "settlements" {
  bucket = aws_s3_bucket.settlements.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = data.aws_kms_alias.data.target_key_arn
    }
    # One data key per bucket for a while instead of one KMS call per object.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "settlements" {
  bucket = aws_s3_bucket.settlements.id

  rule {
    id     = "clean-up"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  # Versioning must be on before rules about noncurrent versions apply.
  depends_on = [aws_s3_bucket_versioning.settlements]
}

# Requests without TLS are refused, whoever makes them.
data "aws_iam_policy_document" "settlements_bucket" {
  statement {
    sid     = "TlsOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.settlements.arn,
      "${aws_s3_bucket.settlements.arn}/*",
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
}

resource "aws_s3_bucket_policy" "settlements" {
  bucket = aws_s3_bucket.settlements.id
  policy = data.aws_iam_policy_document.settlements_bucket.json

  # The public access block must exist first, or a policy could briefly apply without it.
  depends_on = [aws_s3_bucket_public_access_block.settlements]
}
