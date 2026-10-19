# Drill 4: lose a Tokyo AZ, modelled on the 2019 apne1-az4 cooling failure. Pass: 0 lost; API errors
# under 1% for under 2 minutes; no new nodes needed (docs/scope.md §9).
#
# An approximation of AWS's "AZ Availability: Power Interruption" scenario, shortened from 30 to
# az_impairment_minutes (default 10). Everything starts at once:
#
#   minute 0                        nodes in the AZ power off (Karpenter's and the system node group's)
#   minute 0 .. impairment          no new EC2 capacity in the AZ, for Karpenter and for the node group
#   minute 0 .. network             all traffic in and out of the AZ's subnets dropped (NAT gateway too)
#   minute 0                        Aurora fails over, if its writer is in the AZ
#   network .. impairment           zonal shift moves EKS and ALB traffic out of the AZ, as autoshift would
#   impairment                      nodes power back on; capacity and traffic return
#
# Not included: EBS pause-I/O (no workload keeps state on EBS) and ElastiCache (none). The gray-failure
# variant of drill 4 is a separate template, written when that drill is prepared.
# Cost at the defaults: about 41 action-minutes, ~$4.10 per run.

locals {
  impairment_duration = "PT${var.az_impairment_minutes}M"
  network_duration    = "PT${var.network_disruption_minutes}M"
  zonal_shift_minutes = var.az_impairment_minutes - var.network_disruption_minutes
}

resource "aws_fis_experiment_template" "az_power" {
  description = "Drill 4: power interruption in ${var.impaired_az_id}, ${var.az_impairment_minutes} minutes"
  role_arn    = aws_iam_role.fis_az_power.arn

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = aws_cloudwatch_metric_alarm.api_errors.arn
  }

  ##############################################################################
  # Targets
  ##############################################################################

  # Every EKS node in the AZ: tagged by infra/platform (system node group) and the EC2NodeClass (Karpenter).
  target {
    name           = "nodes-in-az"
    resource_type  = "aws:ec2:instance"
    selection_mode = "ALL"

    resource_tag {
      key   = "AzImpairmentPower"
      value = "StopInstances"
    }

    filter {
      path   = "Placement.AvailabilityZone"
      values = [data.aws_availability_zone.impaired.name]
    }

    filter {
      path   = "State.Name"
      values = ["running"]
    }
  }

  target {
    name           = "system-node-group"
    resource_type  = "aws:ec2:autoscaling-group"
    selection_mode = "ALL"
    resource_arns  = [data.aws_autoscaling_group.system.arn]
  }

  target {
    name           = "karpenter-controller-role"
    resource_type  = "aws:iam:role"
    selection_mode = "ALL"
    resource_arns  = [data.aws_iam_role.karpenter_controller.arn]
  }

  # Every subnet of the VPC in the AZ: private, public (the NAT gateway), intra and database.
  target {
    name           = "subnets-in-az"
    resource_type  = "aws:ec2:subnet"
    selection_mode = "ALL"

    parameters = {
      availabilityZoneIdentifier = var.impaired_az_id
      vpc                        = data.aws_vpc.this.id
    }
  }

  # Selected only if the writer is in the AZ; otherwise the action is skipped (the reader there just stops).
  target {
    name           = "aurora-writer-in-az"
    resource_type  = "aws:rds:cluster"
    selection_mode = "ALL"

    resource_tag {
      key   = "AzImpairmentPower"
      value = "DisruptRds"
    }

    parameters = {
      writerAvailabilityZoneIdentifiers = data.aws_availability_zone.impaired.name
    }
  }

  # The EKS cluster (tagged in infra/platform) and the API's ALB (tagged by its Ingress annotation).
  target {
    name           = "zonal-shift-resources"
    resource_type  = "aws:arc:zonal-shift-managed-resource"
    selection_mode = "ALL"

    resource_tag {
      key   = "AzImpairmentPower"
      value = "RecoverAutoshiftResources"
    }
  }

  ##############################################################################
  # Actions
  ##############################################################################

  action {
    name        = "stop-nodes"
    action_id   = "aws:ec2:stop-instances"
    description = "Power off every node in the AZ; restart them when the impairment ends"

    parameter {
      key   = "startInstancesAfterDuration"
      value = local.impairment_duration
    }

    # The node group may replace a stopped node while it is down; don't fail when it can't be restarted.
    parameter {
      key   = "completeIfInstancesTerminated"
      value = "true"
    }

    target {
      key   = "Instances"
      value = "nodes-in-az"
    }
  }

  action {
    name        = "pause-node-group-launches"
    action_id   = "aws:ec2:asg-insufficient-instance-capacity-error"
    description = "The system node group cannot launch in the AZ"

    parameter {
      key   = "availabilityZoneIdentifiers"
      value = var.impaired_az_id
    }

    parameter {
      key   = "duration"
      value = local.impairment_duration
    }

    parameter {
      key   = "percentage"
      value = "100"
    }

    target {
      key   = "AutoScalingGroups"
      value = "system-node-group"
    }
  }

  action {
    name        = "pause-karpenter-launches"
    action_id   = "aws:ec2:api-insufficient-instance-capacity-error"
    description = "Karpenter cannot launch in the AZ"

    parameter {
      key   = "availabilityZoneIdentifiers"
      value = var.impaired_az_id
    }

    parameter {
      key   = "duration"
      value = local.impairment_duration
    }

    parameter {
      key   = "percentage"
      value = "100"
    }

    target {
      key   = "Roles"
      value = "karpenter-controller-role"
    }
  }

  action {
    name        = "drop-network"
    action_id   = "aws:network:disrupt-connectivity"
    description = "Drop all traffic in and out of the AZ's subnets while DNS still points at it"

    parameter {
      key   = "scope"
      value = "all"
    }

    parameter {
      key   = "duration"
      value = local.network_duration
    }

    target {
      key   = "Subnets"
      value = "subnets-in-az"
    }
  }

  action {
    name        = "failover-aurora"
    action_id   = "aws:rds:failover-db-cluster"
    description = "Promote the reader if the writer is in the AZ"

    target {
      key   = "Clusters"
      value = "aurora-writer-in-az"
    }
  }

  action {
    name        = "zonal-shift"
    action_id   = "aws:arc:start-zonal-autoshift"
    description = "Shift EKS and ALB traffic out of the AZ for the rest of the impairment"
    start_after = ["drop-network"]

    parameter {
      key   = "availabilityZoneIdentifier"
      value = var.impaired_az_id
    }

    parameter {
      key   = "duration"
      value = "PT${local.zonal_shift_minutes}M"
    }

    parameter {
      key   = "managedResourceTypes"
      value = "EKS,ALB"
    }

    # ANY: the resources are registered for zonal shift, but autoshift itself is not turned on.
    parameter {
      key   = "zonalAutoshiftStatus"
      value = "ANY"
    }

    target {
      key   = "ManagedResources"
      value = "zonal-shift-resources"
    }
  }

  experiment_options {
    account_targeting = "single-account"
    # As in AWS's scenario: an action with nothing to act on (e.g. the writer is elsewhere) is skipped.
    empty_target_resolution_mode = "skip"
  }

  log_configuration {
    log_schema_version = 2

    cloudwatch_logs_configuration {
      log_group_arn = "${aws_cloudwatch_log_group.fis.arn}:*"
    }
  }

  tags = {
    Name = "${var.name}-drill-04-az-power"
  }
}
