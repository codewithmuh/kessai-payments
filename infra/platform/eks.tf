# EKS control plane, managed add-ons and one small "system" node group.
#
# Boundary: Terraform owns AWS resources. Everything that runs *inside* the cluster, including the
# Karpenter controller and its NodePools, is installed by Argo CD from git.
# The system node group exists so those controllers have somewhere to run before Karpenter does.
# Compute is EC2 only, no Fargate: FIS's AZ actions stop EC2 instances and ARC zonal shift moves
# traffic away from EC2 nodes; neither works on Fargate pods.

locals {
  # Cluster-admin and KMS key admin: the CI role that runs the apply workflow (made by infra/bootstrap),
  # so it can clean up before destroy, plus the people in admin_principal_arns.
  cluster_admin_arns = distinct(concat(
    ["arn:aws:iam::${var.account_id}:role/kessai-github-apply"],
    var.admin_principal_arns,
  ))
}

# Two scanner findings are deliberate trade-offs (proposed — ADR pending):
#   AWS-0040  The public API endpoint exists so kubectl works from a laptop. Only api_allowed_cidrs
#             can reach it, and a validation forbids 0.0.0.0/0.
#   AWS-0104  Nodes may send traffic to any address: they pull images from public registries and call
#             AWS APIs through the NAT gateway. Pod egress is narrowed by default-deny NetworkPolicies.
#   AWS-0038  Control-plane logs: api, audit and authenticator only. controllerManager and scheduler
#             logs add CloudWatch cost and are not needed for the drills.
#trivy:ignore:AWS-0040
#trivy:ignore:AWS-0104
#trivy:ignore:AWS-0038
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  # At the end of standard support, auto-upgrade instead of paying for extended support
  # ($0.50 per cluster-hour instead of $0.10).
  upgrade_policy = {
    support_type = "STANDARD"
  }

  # Registers the cluster with ARC zonal shift, so traffic to pods can be moved away from one AZ
  # (by hand, or by the FIS zonal-autoshift action in drill 4). Free; nothing moves until a shift starts.
  zonal_shift_config = {
    enabled = true
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  # Nodes use the private endpoint. The public one exists for kubectl from a laptop, and only the
  # CIDRs in api_allowed_cidrs can reach it. Argo CD pulls from git, so CI deploys never need the API;
  # only the teardown does, and infra/scripts/pre-destroy.sh adds the runner's IP for that.
  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.api_allowed_cidrs

  # Access entries only (no aws-auth ConfigMap). AWS Backup for EKS and the FIS pod actions also need
  # API mode: both get into the cluster through access entries. Admins are listed explicitly rather than
  # "whoever runs apply": you and CI both apply, and a caller-based admin would flip on every run.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    for arn in local.cluster_admin_arns : arn => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Pods get AWS credentials through EKS Pod Identity, so the IRSA OIDC provider is not needed.
  enable_irsa = false

  # Kubernetes Secrets are envelope-encrypted with a KMS key the module creates. The same fixed
  # admins manage the key (the module's default is the caller, which would flip like above).
  encryption_config = {
    resources = ["secrets"]
  }
  kms_key_administrators = local.cluster_admin_arns

  enabled_log_types                      = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  addons = {
    # Prefix delegation hands each node /28 prefixes instead of single IPs: a t4g.medium goes from
    # 17 pods to 110. It must be set before nodes join, hence before_compute.
    # enableNetworkPolicy turns on the VPC CNI's NetworkPolicy agent; without it every NetworkPolicy
    # (default-deny, "only the API and workers reach the database") is accepted and silently ignored.
    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}
    # Volumes for Prometheus. Payments never live on a volume: Aurora is the only system of record.
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = var.system_node_instance_types
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      iam_role_name = "${var.name}-system-node"
      iam_role_additional_policies = {
        # Shell access through SSM Session Manager instead of SSH keys and open ports.
        ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      # Drill 4 (infra/fis) stops every node in one AZ and finds them by this tag, the default of AWS's
      # "AZ Availability: Power Interruption" scenario. Karpenter's EC2NodeClass sets the same tag.
      launch_template_tags = {
        AzImpairmentPower = "StopInstances"
      }

      labels = {
        "node-pool" = "system"
      }

      # Only cluster-critical pods (CoreDNS, Karpenter, Argo CD, ...) tolerate this, so application
      # pods always land on Karpenter nodes and can never starve the controllers.
      taints = {
        critical-addons-only = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      block_device_mappings = {
        root = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 30
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }

  # Drill 4's zonal-shift action finds the cluster by this tag (the scenario's default tag again).
  cluster_tags = {
    AzImpairmentPower = "RecoverAutoshiftResources"
  }

  # Karpenter finds the node security group by this tag (EC2NodeClass securityGroupSelectorTerms),
  # and infra/data allows PostgreSQL from this security group.
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.name
  }
}
