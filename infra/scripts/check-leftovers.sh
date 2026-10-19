#!/usr/bin/env bash
# Lists anything still billing in the Kessai region and exits 1 if there is something. make aws-down runs
# it after the per-session stacks are destroyed.
#
# It assumes a dedicated AWS account: everything it finds counts, whether Terraform, a Kubernetes
# controller or a person created it. Not checked, because they are meant to outlive the session and cost
# nothing or close to it: the state bucket, the money-data KMS key, the AWS Backup vault and its recovery
# points (expire after 1 day), Aurora final snapshots (cents a month; listed below for information), FIS
# experiment log groups (expire on their own), KMS keys pending deletion and the budgets.
set -euo pipefail

# shellcheck source=infra/scripts/common.sh
source "$(dirname "$0")/common.sh"

REGION="${KESSAI_REGION:-ap-northeast-1}"

require_kessai_account

leftovers=""

# add <kind> <rows>: one table line per row of `aws ... --output text` (fields are tab-separated).
add() {
  local kind=$1 rows=$2 row
  if [ -z "$rows" ]; then
    return 0
  fi
  while IFS= read -r row; do
    leftovers+=$(printf '%-24s %s' "$kind" "${row//$'\t'/  }")$'\n'
  done <<<"$rows"
}

echo "Checking $REGION for billable leftovers..."

# Each query is assigned to a variable first, so a failed call stops the script (set -e) instead of
# looking like "nothing found".
clusters=$(aws eks list-clusters --region "$REGION" --query 'clusters[]' --output text | tr '\t' '\n')
add "EKS cluster" "$clusters"

instances=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' --output text)
add "EC2 instance" "$instances"

db_clusters=$(aws rds describe-db-clusters --region "$REGION" \
  --query 'DBClusters[].[DBClusterIdentifier,Engine,Status]' --output text)
add "Aurora cluster" "$db_clusters"

db_instances=$(aws rds describe-db-instances --region "$REGION" \
  --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus]' --output text)
add "DB instance" "$db_instances"

# describe-nat-gateways spells it --filter, unlike the other EC2 calls.
nat_gateways=$(aws ec2 describe-nat-gateways --region "$REGION" \
  --filter "Name=state,Values=pending,available" \
  --query 'NatGateways[].[NatGatewayId,VpcId,State]' --output text)
add "NAT gateway" "$nat_gateways"

volumes=$(aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=status,Values=available" \
  --query 'Volumes[].[VolumeId,VolumeType,Size]' --output text)
add "EBS volume (unattached)" "$volumes"

load_balancers=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query 'LoadBalancers[].[LoadBalancerName,Type,State.Code]' --output text)
add "Load balancer" "$load_balancers"

classic_load_balancers=$(aws elb describe-load-balancers --region "$REGION" \
  --query 'LoadBalancerDescriptions[].[LoadBalancerName]' --output text)
add "Classic load balancer" "$classic_load_balancers"

# shellcheck disable=SC2016 # the backticks are a JMESPath literal, not shell
addresses=$(aws ec2 describe-addresses --region "$REGION" \
  --query 'Addresses[?AssociationId==`null`].[PublicIp,AllocationId]' --output text)
add "Elastic IP (unattached)" "$addresses"

# A drill still running keeps billing per action-minute (and keeps nodes stopped or traffic shifted).
# shellcheck disable=SC2016 # the backticks are a JMESPath literal, not shell
experiments=$(aws fis list-experiments --region "$REGION" \
  --query 'experiments[?contains([`pending`, `initiating`, `running`, `stopping`], state.status)].[id,experimentTemplateId,state.status]' \
  --output text)
add "FIS experiment" "$experiments"

# For information only: final snapshots kept from earlier sessions (storage only, a few cents a month).
snapshots=$(aws rds describe-db-cluster-snapshots --region "$REGION" --snapshot-type manual \
  --query 'DBClusterSnapshots[].[DBClusterSnapshotIdentifier,AllocatedStorage]' --output text)
if [ -n "$snapshots" ]; then
  echo "Kept on purpose (not a failure): Aurora snapshots, GiB"
  echo "$snapshots"
fi

if [ -z "$leftovers" ]; then
  echo "Nothing billable left in $REGION."
  exit 0
fi

echo
printf '%-24s %s\n' "RESOURCE" "DETAILS"
printf '%s' "$leftovers"
echo
echo "Billable resources are still running in $REGION. Run make aws-down again or delete them by hand." >&2
exit 1
