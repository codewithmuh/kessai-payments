# Aurora Global Database, on DR days only (enable_global_database = true). The Tokyo cluster becomes the
# primary of a global cluster, and the Osaka secondary (Phase 3) joins it. Replication runs in the storage
# layer, typically under a second behind: a switchover loses nothing (drill 9), a failover loses at most
# that lag (drill 10).
#
# What the flag also changes:
#   - Instances must be r-class (validated in variables.tf), which roughly doubles the database bill.
#   - Aurora cannot manage the master password in Secrets Manager inside a global database. The password
#     moves to a secret this stack owns (kessai/db-master). It is generated during the apply and sent
#     write-only, so it is never stored in Terraform state.

resource "aws_rds_global_cluster" "this" {
  count = var.enable_global_database ? 1 : 0

  global_cluster_identifier    = "${var.name}-global"
  source_db_cluster_identifier = aws_rds_cluster.this.arn
  # On destroy, detach the Tokyo cluster instead of failing. The Osaka secondary must be removed first.
  force_destroy = true
}

ephemeral "random_password" "master" {
  count = var.enable_global_database ? 1 : 0

  length = 32
  # RDS refuses /, @, " and spaces in a master password.
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "master" {
  #checkov:skip=CKV2_AWS_57:This secret exists on DR days only; RDS-managed rotation comes back when the flag is turned off.
  count = var.enable_global_database ? 1 : 0

  name        = "${var.name}/db-master"
  description = "Aurora master user while the cluster is in a Global Database (RDS-managed passwords are off then)"
  kms_key_id  = data.aws_kms_alias.data.target_key_arn
  # Deleted at once when the flag goes back to false, so the name is free for the next DR day.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "master" {
  count = var.enable_global_database ? 1 : 0

  secret_id = aws_secretsmanager_secret.master[0].id
  # The same value aurora.tf sends as master_password_wo: both are written in this one apply.
  secret_string_wo = jsonencode({
    username = aws_rds_cluster.this.master_username
    password = ephemeral.random_password.master[0].result
  })
  secret_string_wo_version = 1
}
