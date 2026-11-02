# IAM roles for in-cluster controllers, handed out with EKS Pod Identity: each service account gets
# exactly one role, and no pod can use the node's credentials (IMDS hop limit is 1).
# The controllers are installed by Argo CD; their namespace and service account must match these.
# Roles for Kessai's own workloads (SQS, settlement files) live in infra/data, next to what they use.

# The money-data key from infra/bootstrap. Looked up rather than assumed, so a plan fails here (not in
# the cluster) if infra/bootstrap has not been applied: `make aws-bootstrap`.
data "aws_kms_alias" "data" {
  name = "alias/kessai-data"
}

module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name               = "${var.name}-ebs-csi"
  policy_name_prefix = "${var.name}-"

  attach_aws_ebs_csi_policy = true
  # The association is made by the aws-ebs-csi-driver add-on in eks.tf.
}

module "aws_lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name               = "${var.name}-aws-lb-controller"
  policy_name_prefix = "${var.name}-"

  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name = module.eks.cluster_name
      # Controllers that create AWS resources live in kube-system, so tearing down app namespaces
      # never removes the controller before it has deleted its load balancers (infra/scripts/pre-destroy.sh).
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  # A fixed name: infra/data adds read access to the database secret, which Aurora names itself (rds!cluster-...).
  name               = "${var.name}-external-secrets"
  use_name_prefix    = false
  policy_name_prefix = "${var.name}-"

  attach_external_secrets_policy = true
  # Read-only, and only secrets under the "kessai/" path in Secrets Manager.
  external_secrets_secrets_manager_arns = ["arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.name}/*"]
  external_secrets_create_permission    = false
  # Those secrets are encrypted with the money-data key; without this the module allows decrypting with any key.
  external_secrets_kms_key_arns = [data.aws_kms_alias.data.target_key_arn]

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
}
