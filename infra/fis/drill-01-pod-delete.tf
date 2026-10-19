# Drill 1: kill API and worker pods in the middle of traffic. Pass: 0 acknowledged payments lost, and no
# duplicate effects at merchant-sim (docs/scope.md §9).
#
# gracePeriodSeconds 0 is a crash, not a shutdown: no SIGTERM, no draining. Graceful shutdown is drill 3.
# FIS starts a pod of its own in the app namespace to do the deleting; it needs the service account and
# RBAC Role in infra/README.md ("FIS inside the cluster"). Cost: two one-shot actions, about $0.20.

resource "aws_fis_experiment_template" "pod_delete" {
  description = "Drill 1: kill Kessai API and worker pods mid-traffic"
  role_arn    = aws_iam_role.fis_pod_delete.arn

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = aws_cloudwatch_metric_alarm.api_errors.arn
  }

  target {
    name           = "api-pods"
    resource_type  = "aws:eks:pod"
    selection_mode = var.api_pod_selection

    parameters = {
      clusterIdentifier = data.aws_eks_cluster.this.name
      namespace         = var.app_namespace
      selectorType      = "labelSelector"
      selectorValue     = var.api_pod_selector
    }
  }

  target {
    name           = "worker-pods"
    resource_type  = "aws:eks:pod"
    selection_mode = var.worker_pod_selection

    parameters = {
      clusterIdentifier = data.aws_eks_cluster.this.name
      namespace         = var.app_namespace
      selectorType      = "labelSelector"
      selectorValue     = var.worker_pod_selector
    }
  }

  action {
    name        = "delete-api-pods"
    action_id   = "aws:eks:pod-delete"
    description = "Crash API pods while clients keep paying"

    parameter {
      key   = "kubernetesServiceAccount"
      value = var.fis_kubernetes_name
    }

    parameter {
      key   = "gracePeriodSeconds"
      value = "0"
    }

    target {
      key   = "Pods"
      value = "api-pods"
    }
  }

  action {
    name        = "delete-worker-pods"
    action_id   = "aws:eks:pod-delete"
    description = "Crash outbox-relay and webhook-sender pods mid-delivery"

    parameter {
      key   = "kubernetesServiceAccount"
      value = var.fis_kubernetes_name
    }

    parameter {
      key   = "gracePeriodSeconds"
      value = "0"
    }

    target {
      key   = "Pods"
      value = "worker-pods"
    }
  }

  experiment_options {
    account_targeting = "single-account"
    # No pods found means the app is not running: fail instead of reporting a pass.
    empty_target_resolution_mode = "fail"
  }

  log_configuration {
    log_schema_version = 2

    cloudwatch_logs_configuration {
      log_group_arn = "${aws_cloudwatch_log_group.fis.arn}:*"
    }
  }

  tags = {
    Name = "${var.name}-drill-01-pod-delete"
  }

  # The template is useless without the access entry, so it is created after it and destroyed before it.
  depends_on = [aws_eks_access_entry.fis_pod_delete]
}
