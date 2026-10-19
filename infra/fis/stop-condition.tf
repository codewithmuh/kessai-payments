# Every drill stops on its own if the API keeps failing: more than stop_error_rate_percent of requests
# answered with 5xx for stop_after_minutes minutes in a row. 5xx from the load balancer itself (no healthy
# target: 502, 503, 504) and from the pods both count. Measured at the ALB, the same path the payment
# client uses. No traffic means no data, which never stops a drill.

resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name          = "${var.name}-drill-stop-api-errors"
  alarm_description   = "Stops running FIS drills: more than ${var.stop_error_rate_percent}% of API requests failed for ${var.stop_after_minutes} minutes in a row."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.stop_error_rate_percent
  evaluation_periods  = var.stop_after_minutes
  datapoints_to_alarm = var.stop_after_minutes
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    label       = "API 5xx rate (%)"
    expression  = "100 * (FILL(elb_5xx, 0) + FILL(target_5xx, 0)) / requests"
    return_data = true
  }

  metric_query {
    id = "elb_5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      dimensions  = { LoadBalancer = data.aws_lb.api.arn_suffix }
      period      = 60
      stat        = "Sum"
    }
  }

  metric_query {
    id = "target_5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = { LoadBalancer = data.aws_lb.api.arn_suffix }
      period      = 60
      stat        = "Sum"
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = { LoadBalancer = data.aws_lb.api.arn_suffix }
      period      = 60
      stat        = "Sum"
    }
  }
}

# Each experiment writes its timeline here (log schema v2): which targets it picked, when each action
# started and ended. That is the injection side of the postmortem timeline, so it must outlive the
# session: one log group per session, left behind by `terraform destroy` (skip_destroy), deleted by
# CloudWatch itself after log_retention_days.
resource "terraform_data" "session" {
  input = formatdate("YYYYMMDD'T'hhmm'Z'", plantimestamp())

  lifecycle {
    ignore_changes = [input]
  }
}

# AWS-0017: FIS action events only (resource IDs, timestamps); see the checkov skip below.
#trivy:ignore:AWS-0017
resource "aws_cloudwatch_log_group" "fis" {
  #checkov:skip=CKV_AWS_158:The log holds FIS action events (resource IDs, timestamps), no payment data; a KMS key would need a CloudWatch Logs key-policy statement.
  #checkov:skip=CKV_AWS_338:30 days covers writing the postmortem; drills are re-run, not audited.
  name              = "/aws/fis/${var.name}/${terraform_data.session.output}"
  retention_in_days = var.log_retention_days
  skip_destroy      = true
}
