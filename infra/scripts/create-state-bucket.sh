#!/usr/bin/env bash
# Creates the S3 bucket that holds Terraform state for one account, or puts an existing one back to these
# settings. A script because a Terraform stack cannot keep its state in a bucket it creates itself.
#
#   create-state-bucket.sh workload   kessai-tfstate-<KESSAI_ACCOUNT_ID>, in KESSAI_REGION (Tokyo)
#   create-state-bucket.sh backup     kessai-tfstate-<KESSAI_BACKUP_ACCOUNT_ID>, in KESSAI_BACKUP_REGION (Osaka)
#
# Run once per account (make aws-bootstrap and make backup-account do), with that account's AWS_PROFILE.
set -euo pipefail

# shellcheck source=infra/scripts/common.sh
source "$(dirname "$0")/common.sh"

case "${1:-}" in
  workload)
    ACCOUNT_VAR=KESSAI_ACCOUNT_ID
    REGION="${KESSAI_REGION:-ap-northeast-1}"
    ;;
  backup)
    ACCOUNT_VAR=KESSAI_BACKUP_ACCOUNT_ID
    REGION="${KESSAI_BACKUP_REGION:-ap-northeast-3}"
    ;;
  *)
    echo "Usage: $0 workload|backup" >&2
    exit 2
    ;;
esac

require_aws_profile
require_account "$ACCOUNT_VAR"

ACCOUNT_ID="${!ACCOUNT_VAR}"
BUCKET="kessai-tfstate-${ACCOUNT_ID}"

# --expected-bucket-owner: a bucket with this name in someone else's account counts as "not ours".
# create-bucket then fails with BucketAlreadyExists, which is the right outcome.
if aws s3api head-bucket --region "$REGION" --bucket "$BUCKET" --expected-bucket-owner "$ACCOUNT_ID" 2>/dev/null; then
  echo "Bucket $BUCKET exists; re-applying its settings."
else
  echo "Creating bucket $BUCKET in $REGION..."
  aws s3api create-bucket --region "$REGION" --bucket "$BUCKET" \
    --create-bucket-configuration "LocationConstraint=$REGION" \
    --object-ownership BucketOwnerEnforced
fi

# Never public, whatever a later policy or ACL says.
aws s3api put-public-access-block --region "$REGION" --bucket "$BUCKET" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# ACLs off: the bucket owner owns every object, and access is decided by IAM and the bucket policy only.
aws s3api put-bucket-ownership-controls --region "$REGION" --bucket "$BUCKET" \
  --ownership-controls "Rules=[{ObjectOwnership=BucketOwnerEnforced}]"

# Every state write keeps the previous version, so a broken state file can be rolled back.
aws s3api put-bucket-versioning --region "$REGION" --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

# Encrypted at rest with S3-managed keys. The bucket key only matters if this moves to SSE-KMS later.
aws s3api put-bucket-encryption --region "$REGION" --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}, "BucketKeyEnabled": true}]
  }'

# Refuse plain HTTP: state files can contain secrets.
tls_only_policy=$(
  cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyInsecureTransport",
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:*",
    "Resource": ["arn:aws:s3:::${BUCKET}", "arn:aws:s3:::${BUCKET}/*"],
    "Condition": {"Bool": {"aws:SecureTransport": "false"}}
  }]
}
EOF
)
aws s3api put-bucket-policy --region "$REGION" --bucket "$BUCKET" --policy "$tls_only_policy"

# Old state versions go after 90 days. Every plan and apply writes and deletes a lock file, which on
# a versioned bucket leaves a delete marker; ExpiredObjectDeleteMarker cleans those up too.
aws s3api put-bucket-lifecycle-configuration --region "$REGION" --bucket "$BUCKET" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-old-state-versions",
      "Status": "Enabled",
      "Filter": {"Prefix": ""},
      "NoncurrentVersionExpiration": {"NoncurrentDays": 90},
      "AbortIncompleteMultipartUpload": {"DaysAfterInitiation": 7},
      "Expiration": {"ExpiredObjectDeleteMarker": true}
    }]
  }'

aws s3api put-bucket-tagging --region "$REGION" --bucket "$BUCKET" \
  --tagging "TagSet=[{Key=Project,Value=kessai},{Key=Stack,Value=state},{Key=ManagedBy,Value=infra/scripts/create-state-bucket.sh}]"

echo "State bucket ready: $BUCKET ($REGION)"
