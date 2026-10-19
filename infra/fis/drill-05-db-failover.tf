# Drill 5: fail the database over while clients retry with the same idempotency keys. Pass: 0 lost;
# exactly one payment per key; a writer again within 60 s (docs/scope.md §9).
#
# The client side of the drill (same-key retries) runs from the laptop; FIS only does the failover, so
# the moment of injection is in the FIS log. Cost: one action, about $0.10.

resource "aws_fis_experiment_template" "db_failover" {
  description = "Drill 5: Aurora failover while clients retry the same idempotency keys"
  role_arn    = aws_iam_role.fis_db_failover.arn

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = aws_cloudwatch_metric_alarm.api_errors.arn
  }

  target {
    name           = "aurora"
    resource_type  = "aws:rds:cluster"
    selection_mode = "ALL"
    resource_arns  = [data.aws_rds_cluster.this.arn]
  }

  action {
    name        = "failover-aurora"
    action_id   = "aws:rds:failover-db-cluster"
    description = "Promote the reader to writer"

    target {
      key   = "Clusters"
      value = "aurora"
    }
  }

  experiment_options {
    account_targeting            = "single-account"
    empty_target_resolution_mode = "fail"
  }

  log_configuration {
    log_schema_version = 2

    cloudwatch_logs_configuration {
      log_group_arn = "${aws_cloudwatch_log_group.fis.arn}:*"
    }
  }

  tags = {
    Name = "${var.name}-drill-05-db-failover"
  }
}
