# What this stack uses from infra/bootstrap and infra/platform, looked up by name rather than read from
# their state. A plan fails here, with a clear "not found", if those stacks have not been applied.

data "aws_kms_alias" "data" {
  name = "alias/kessai-data"
}

data "aws_vpc" "this" {
  tags = {
    Name = var.name
  }
}

data "aws_db_subnet_group" "this" {
  name = var.name
}

# The EKS node security group (tagged for Karpenter in infra/platform/eks.tf). Pods use their node's
# security group, so this is the source the database accepts connections from.
data "aws_security_group" "nodes" {
  vpc_id = data.aws_vpc.this.id

  tags = {
    "karpenter.sh/discovery" = var.name
  }
}

data "aws_eks_cluster" "this" {
  name = var.name
}

# Made by infra/platform/pod-identity.tf; aurora.tf lets it read the database secret.
data "aws_iam_role" "external_secrets" {
  name = "${var.name}-external-secrets"
}

data "aws_availability_zone" "db" {
  for_each = toset(var.db_instance_az_ids)

  zone_id = each.key
}
