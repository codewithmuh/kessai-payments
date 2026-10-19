# Shared by the scripts in this folder and by infra/Makefile. Source it; don't run it.
# shellcheck shell=bash

# AWS CLI v2 pipes long output through a pager; a script must never wait for a keypress.
export AWS_PAGER=""

# Stops unless AWS_PROFILE is set, so the machine's default AWS identity is never used by accident.
require_aws_profile() {
  if [ -z "${AWS_PROFILE:-}" ]; then
    echo "Set AWS_PROFILE to your personal Kessai AWS profile first (export AWS_PROFILE=...)." >&2
    exit 1
  fi
}

# require_account <variable name>: stops unless the credentials in use belong to the account whose ID is in
# that variable. This is the real guard: it holds whichever way the credentials were found (profile,
# environment variables or CI's OIDC role).
require_account() {
  local var_name=$1
  local expected=${!var_name:-}
  if [ -z "$expected" ]; then
    echo "Set $var_name to the 12-digit ID of that AWS account." >&2
    exit 1
  fi
  local account
  account=$(aws sts get-caller-identity --query Account --output text)
  if [ "$account" != "$expected" ]; then
    # IDs are not printed: in CI this line would end up in a public log.
    echo "These AWS credentials are not for $var_name. Stopping before touching anything." >&2
    exit 1
  fi
}

# The workload account: everything except infra/backup-account.
require_kessai_account() {
  require_account KESSAI_ACCOUNT_ID
}

# The separate backup account (infra/backup-account), used with its own AWS_PROFILE.
require_backup_account() {
  require_account KESSAI_BACKUP_ACCOUNT_ID
}

# This machine's public IPv4 address, as AWS sees it.
my_public_ip() {
  curl -fsS --max-time 10 https://checkip.amazonaws.com
}

# The CIDRs that may reach the Kubernetes API, as a Terraform list: API_ALLOWED_CIDRS if it is set,
# otherwise this machine's public IP as a /32.
api_allowed_cidrs() {
  if [ -n "${API_ALLOWED_CIDRS:-}" ]; then
    echo "$API_ALLOWED_CIDRS"
    return 0
  fi
  local ip
  ip=$(my_public_ip) || return 1
  echo "[\"$ip/32\"]"
}
