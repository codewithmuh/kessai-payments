# What the drills target, looked up by name. Apply this stack last, after infra/platform, infra/data and
# the app (which creates the load balancer); a plan fails here with "not found" if something is missing.

data "aws_eks_cluster" "this" {
  name = var.name
}

data "aws_vpc" "this" {
  tags = {
    Name = var.name
  }
}

data "aws_rds_cluster" "this" {
  cluster_identifier = var.name
}

# Created by the AWS Load Balancer Controller from the API's Ingress.
data "aws_lb" "api" {
  name = var.alb_name
}

# Karpenter's controller role (infra/platform/karpenter.tf). Drill 4 makes its EC2 launches fail in the AZ.
data "aws_iam_role" "karpenter_controller" {
  name = "${var.name}-karpenter-controller"
}

# The system node group's Auto Scaling group, which EKS names. Drill 4 makes its launches fail in the AZ.
data "aws_eks_node_groups" "this" {
  cluster_name = data.aws_eks_cluster.this.name
}

data "aws_eks_node_group" "system" {
  cluster_name    = data.aws_eks_cluster.this.name
  node_group_name = one([for n in data.aws_eks_node_groups.this.names : n if startswith(n, "system")])
}

data "aws_autoscaling_group" "system" {
  name = data.aws_eks_node_group.system.resources[0].autoscaling_groups[0].name
}

# FIS filters EC2 instances by AZ name (apne1-az4 is "ap-northeast-1a" in some accounts, "1c" in others).
data "aws_availability_zone" "impaired" {
  zone_id = var.impaired_az_id
}
