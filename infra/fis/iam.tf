# One role per drill, each allowed exactly the faults of its drill. AWS's managed FIS policies are broader
# (AWSFaultInjectionSimulatorEC2Access may stop any instance and run SSM commands on it), so these are
# written out, following the policy AWS publishes for the AZ Power Interruption scenario.

# Only FIS, running an experiment in this account and region, may assume the drill roles.
data "aws_iam_policy_document" "fis_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["fis.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:fis:${var.region}:${var.account_id}:experiment/*"]
    }
  }
}

# Shared by every drill role: write the experiment log (stop-condition.tf). These log-delivery calls
# do not support resource-level permissions.
data "aws_iam_policy_document" "fis_logging" {
  #checkov:skip=CKV_AWS_111:logs:CreateLogDelivery and logs:PutResourcePolicy accept only Resource "*".
  #checkov:skip=CKV_AWS_356:logs:CreateLogDelivery and logs:PutResourcePolicy accept only Resource "*".
  statement {
    sid = "DeliverExperimentLogs"
    actions = [
      "logs:CreateLogDelivery",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

################################################################################
# Drill 1: delete API and worker pods
################################################################################

data "aws_iam_policy_document" "fis_pod_delete" {
  source_policy_documents = [data.aws_iam_policy_document.fis_logging.json]

  statement {
    sid       = "FindTheCluster"
    actions   = ["eks:DescribeCluster"]
    resources = [data.aws_eks_cluster.this.arn]
  }

  statement {
    sid       = "ResolvePodTargets"
    actions   = ["ec2:DescribeSubnets", "tag:GetResources"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "fis_pod_delete" {
  name               = "${var.name}-fis-pod-delete"
  description        = "FIS drill 1: delete Kessai API and worker pods"
  assume_role_policy = data.aws_iam_policy_document.fis_trust.json
}

resource "aws_iam_role_policy" "fis_pod_delete" {
  name   = "${var.name}-fis-pod-delete"
  role   = aws_iam_role.fis_pod_delete.id
  policy = data.aws_iam_policy_document.fis_pod_delete.json
}

# What deleting pods takes inside the cluster is Kubernetes RBAC, not IAM: this access entry maps the role
# to the Kubernetes user fis_kubernetes_name, which a Role in the app namespace allows to create the FIS
# pod and delete pods (infra/README.md, "FIS inside the cluster"). No access policy: nothing cluster-wide.
resource "aws_eks_access_entry" "fis_pod_delete" {
  cluster_name  = data.aws_eks_cluster.this.name
  principal_arn = aws_iam_role.fis_pod_delete.arn
  user_name     = var.fis_kubernetes_name
  type          = "STANDARD"
}

################################################################################
# Drill 4: AZ power interruption
################################################################################

data "aws_iam_policy_document" "fis_az_power" {
  #checkov:skip=CKV_AWS_111:Describe and tag:GetResources calls, ec2:InjectApiError (narrowed by its action-ID condition) and the ARC calls accept only Resource "*".
  #checkov:skip=CKV_AWS_356:Describe and tag:GetResources calls, ec2:InjectApiError (narrowed by its action-ID condition) and the ARC calls accept only Resource "*".
  source_policy_documents = [data.aws_iam_policy_document.fis_logging.json]

  statement {
    sid = "ResolveTargets"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:DescribeNetworkAcls",
      "ec2:DescribeManagedPrefixLists",
      "ec2:GetManagedPrefixListEntries",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeTags",
      "rds:DescribeDBClusters",
      "tag:GetResources",
    ]
    resources = ["*"]
  }

  # Power off: only nodes tagged for the drill (infra/platform/eks.tf, Karpenter's EC2NodeClass).
  statement {
    sid       = "StopAndRestartDrillNodes"
    actions   = ["ec2:StopInstances", "ec2:StartInstances"]
    resources = ["arn:aws:ec2:${var.region}:${var.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/AzImpairmentPower"
      values   = ["StopInstances"]
    }
  }

  # Restarting a node whose root volume is encrypted needs a KMS grant, made through EC2 only.
  statement {
    sid       = "RestartEncryptedNodes"
    actions   = ["kms:CreateGrant"]
    resources = ["arn:aws:kms:${var.region}:${var.account_id}:key/*"]

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["ec2.${var.region}.amazonaws.com"]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  # No new capacity in the AZ: launches by Karpenter's role and by the system node group fail with
  # InsufficientInstanceCapacity.
  statement {
    sid       = "InjectInsufficientCapacity"
    actions   = ["ec2:InjectApiError"]
    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "ec2:FisActionId"
      values = [
        "aws:ec2:api-insufficient-instance-capacity-error",
        "aws:ec2:asg-insufficient-instance-capacity-error",
      ]
    }
  }

  # Network loss: FIS swaps each subnet's network ACL for a deny-all copy tagged managedByFIS, then
  # restores the original. It may only create, change and delete ACLs carrying that tag.
  statement {
    sid       = "CreateDenyAllNetworkAcl"
    actions   = ["ec2:CreateNetworkAcl"]
    resources = ["arn:aws:ec2:${var.region}:${var.account_id}:network-acl/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/managedByFIS"
      values   = ["true"]
    }
  }

  statement {
    sid       = "CreateNetworkAclInTheVpc"
    actions   = ["ec2:CreateNetworkAcl"]
    resources = [data.aws_vpc.this.arn]
  }

  statement {
    sid       = "TagTheNetworkAcl"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:${var.region}:${var.account_id}:network-acl/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateNetworkAcl"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/managedByFIS"
      values   = ["true"]
    }
  }

  statement {
    sid       = "EditAndDeleteFisNetworkAcls"
    actions   = ["ec2:CreateNetworkAclEntry", "ec2:DeleteNetworkAcl"]
    resources = ["arn:aws:ec2:${var.region}:${var.account_id}:network-acl/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/managedByFIS"
      values   = ["true"]
    }
  }

  statement {
    sid     = "SwapSubnetNetworkAcls"
    actions = ["ec2:ReplaceNetworkAclAssociation"]
    resources = [
      "arn:aws:ec2:${var.region}:${var.account_id}:subnet/*",
      "arn:aws:ec2:${var.region}:${var.account_id}:network-acl/*",
    ]
  }

  # The database: fail the cluster over if its writer is in the AZ.
  statement {
    sid       = "FailoverAurora"
    actions   = ["rds:FailoverDBCluster"]
    resources = [data.aws_rds_cluster.this.arn]
  }

  # Recovery: shift traffic away from the AZ, as zonal autoshift would during a real event.
  statement {
    sid = "ZonalShift"
    actions = [
      "arc-zonal-shift:StartZonalShift",
      "arc-zonal-shift:UpdateZonalShift",
      "arc-zonal-shift:CancelZonalShift",
      "arc-zonal-shift:GetManagedResource",
      "arc-zonal-shift:ListManagedResources",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "fis_az_power" {
  name               = "${var.name}-fis-az-power"
  description        = "FIS drill 4: approximate a power interruption in one Tokyo AZ"
  assume_role_policy = data.aws_iam_policy_document.fis_trust.json
}

resource "aws_iam_role_policy" "fis_az_power" {
  name   = "${var.name}-fis-az-power"
  role   = aws_iam_role.fis_az_power.id
  policy = data.aws_iam_policy_document.fis_az_power.json
}

################################################################################
# Drill 5: Aurora failover
################################################################################

data "aws_iam_policy_document" "fis_db_failover" {
  #checkov:skip=CKV_AWS_356:rds:DescribeDBClusters and tag:GetResources are read-only lookups FIS makes to resolve targets; the failover itself is limited to the cluster's ARN.
  source_policy_documents = [data.aws_iam_policy_document.fis_logging.json]

  statement {
    sid       = "FailoverAurora"
    actions   = ["rds:FailoverDBCluster"]
    resources = [data.aws_rds_cluster.this.arn]
  }

  statement {
    sid       = "ResolveTargets"
    actions   = ["rds:DescribeDBClusters", "tag:GetResources"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "fis_db_failover" {
  name               = "${var.name}-fis-db-failover"
  description        = "FIS drill 5: fail the Kessai Aurora cluster over to its reader"
  assume_role_policy = data.aws_iam_policy_document.fis_trust.json
}

resource "aws_iam_role_policy" "fis_db_failover" {
  name   = "${var.name}-fis-db-failover"
  role   = aws_iam_role.fis_db_failover.id
  policy = data.aws_iam_policy_document.fis_db_failover.json
}
