# AWS permissions for Kessai's own workloads, one role per service account, handed out with EKS Pod
# Identity. The API itself needs no AWS role: it only talks to Aurora, with the password External Secrets
# puts in a Kubernetes Secret.
#
#   outbox-relay    send to the webhook queue
#   webhook-sender  receive and delete from the webhook queue (failures go to the DLQ by redrive policy)
#   mock-bank       write settlement files
#   reconcile       read settlement files, never write them: the job that checks the bank cannot forge it

module "outbox_relay_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                      = "${var.name}-outbox-relay"
  use_name_prefix           = false
  attach_custom_policy      = true
  custom_policy_description = "Kessai outbox-relay: send webhook events to SQS"

  policy_statements = [
    {
      sid       = "SendWebhookEvents"
      actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
      resources = [aws_sqs_queue.webhook_events.arn]
    },
  ]

  associations = {
    this = {
      cluster_name    = data.aws_eks_cluster.this.name
      namespace       = var.app_namespace
      service_account = "outbox-relay"
    }
  }
}

module "webhook_sender_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                      = "${var.name}-webhook-sender"
  use_name_prefix           = false
  attach_custom_policy      = true
  custom_policy_description = "Kessai webhook-sender: consume webhook events from SQS"

  policy_statements = [
    {
      # ChangeMessageVisibility: the sender sets the retry backoff by hiding a failed event for longer.
      sid = "ConsumeWebhookEvents"
      actions = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
      ]
      resources = [aws_sqs_queue.webhook_events.arn]
    },
  ]

  associations = {
    this = {
      cluster_name    = data.aws_eks_cluster.this.name
      namespace       = var.app_namespace
      service_account = "webhook-sender"
    }
  }
}

module "mock_bank_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                      = "${var.name}-mock-bank"
  use_name_prefix           = false
  attach_custom_policy      = true
  custom_policy_description = "Kessai mock-bank: write settlement files"

  policy_statements = [
    {
      sid       = "WriteSettlementFiles"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.settlements.arn}/settlements/*"]
    },
    {
      # The bucket encrypts with the money-data key; S3 calls KMS on the role's behalf, and only S3 may.
      sid       = "EncryptThroughS3"
      actions   = ["kms:GenerateDataKey"]
      resources = [data.aws_kms_alias.data.target_key_arn]
      condition = [{
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${var.region}.amazonaws.com"]
      }]
    },
  ]

  associations = {
    this = {
      cluster_name    = data.aws_eks_cluster.this.name
      namespace       = var.app_namespace
      service_account = "mock-bank"
    }
  }
}

module "reconcile_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                      = "${var.name}-reconcile"
  use_name_prefix           = false
  attach_custom_policy      = true
  custom_policy_description = "Kessai reconcile: read settlement files"

  policy_statements = [
    {
      sid       = "ListSettlementFiles"
      actions   = ["s3:ListBucket"]
      resources = [aws_s3_bucket.settlements.arn]
      condition = [{
        test     = "StringLike"
        variable = "s3:prefix"
        values   = ["settlements/*"]
      }]
    },
    {
      sid       = "ReadSettlementFiles"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.settlements.arn}/settlements/*"]
    },
    {
      sid       = "DecryptThroughS3"
      actions   = ["kms:Decrypt"]
      resources = [data.aws_kms_alias.data.target_key_arn]
      condition = [{
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${var.region}.amazonaws.com"]
      }]
    },
  ]

  associations = {
    this = {
      cluster_name    = data.aws_eks_cluster.this.name
      namespace       = var.app_namespace
      service_account = "reconcile"
    }
  }
}
