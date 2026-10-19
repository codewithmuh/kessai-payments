# The AWS side of Karpenter: controller role (via Pod Identity), node role, the SQS queue and
# EventBridge rules that warn about spot interruptions, and the access entry that lets its nodes join.
# The controller itself and its NodePools are installed by Argo CD, with these values:
#   settings.clusterName       = cluster_name output
#   settings.interruptionQueue = karpenter_queue_name output
#   EC2NodeClass spec.role     = karpenter_node_role_name output
#   EC2NodeClass spec.tags     = { AzImpairmentPower: StopInstances }, so drill 4 stops Karpenter nodes too
# Karpenter launches EC2 instances only (no Fargate), which FIS and ARC zonal shift both need.

# AWS-0342: Karpenter passes the node role to the instance profiles it creates; the module limits
# iam:PassRole to that one role.
#trivy:ignore:AWS-0342
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.29.0"

  cluster_name = module.eks.cluster_name

  # Must match the Helm release: Karpenter runs in kube-system with service account "karpenter".
  namespace       = "kube-system"
  service_account = "karpenter"

  # A fixed name: drill 4 (infra/fis) makes this role's EC2 launches fail in the impaired AZ.
  iam_role_name            = "${var.name}-karpenter-controller"
  iam_role_use_name_prefix = false
  iam_policy_name          = "${var.name}-karpenter-controller"

  # A fixed name (no random suffix), because the EC2NodeClass in git refers to it.
  node_iam_role_name            = "${var.name}-karpenter-node"
  node_iam_role_use_name_prefix = false
  node_iam_role_additional_policies = {
    ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  queue_name = "${var.name}-karpenter"
}
