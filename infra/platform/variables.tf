variable "account_id" {
  description = "The AWS account Kessai runs in (the workload account). The provider refuses every other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region. Tokyo is the primary region; Osaka is the DR region (docs/scope.md §6)."
  type        = string
  default     = "ap-northeast-1"
}

variable "name" {
  description = "Name used for the cluster, the VPC and as the prefix of every IAM role and policy."
  type        = string
  default     = "kessai"

  # The CI apply role may only manage IAM roles and policies named kessai-* (infra/bootstrap).
  validation {
    condition     = var.name == "kessai" || startswith(var.name, "kessai-")
    error_message = "name must be \"kessai\" or start with \"kessai-\", or the CI apply role cannot create its IAM roles."
  }
}

variable "environment" {
  description = "Environment tag. One environment: the platform is created and destroyed per session."
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. 1.36 is in standard support until 2027-08-02; drill 3 upgrades it to 1.37 under load."
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "VPC range. Large private subnets matter because every pod gets a VPC IP (VPC CNI)."
  type        = string
  default     = "10.50.0.0/16"
}

variable "availability_zone_ids" {
  description = "The three AZs, by zone ID. An ID is the same physical AZ in every account (names like 1a and 1c are shuffled per account), and a fixed list never changes when AWS adds an AZ."
  type        = list(string)
  # Tokyo's three general-purpose AZs; apne1-az3 is closed to new subnets. The first one gets the single
  # NAT gateway. apne1-az4 comes first on purpose: drill 4 replays the 2019 apne1-az4 outage, so it
  # also takes out the NAT gateway and shows that single point of failure.
  default = ["apne1-az4", "apne1-az1", "apne1-az2"]

  validation {
    condition     = length(var.availability_zone_ids) == 3
    error_message = "Give exactly three zone IDs; the subnet layout in vpc.tf assumes three AZs."
  }
}

variable "single_nat_gateway" {
  description = "One NAT gateway for all AZs (cheaper; losing its AZ cuts egress for the other two, which drill 4 shows on purpose). Set false for one per AZ."
  type        = bool
  default     = true
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. `make aws-up` sets this to your current IP."
  type        = list(string)

  validation {
    condition     = length(var.api_allowed_cidrs) > 0 && !contains(var.api_allowed_cidrs, "0.0.0.0/0")
    error_message = "Give at least one CIDR, and never 0.0.0.0/0: the API endpoint must not be open to the internet."
  }

  # Catches an empty IP lookup in `make aws-up` ("/32") before AWS rejects it halfway through an apply.
  validation {
    condition     = alltrue([for cidr in var.api_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every entry must be a valid CIDR such as 203.0.113.7/32."
  }
}

variable "admin_principal_arns" {
  description = "Your own IAM role or user ARN(s); they get cluster-admin. The CI apply role (infra/bootstrap) is always added."
  type        = list(string)

  # Required, with no "whoever runs apply" fallback: both you and CI apply this stack, and a
  # caller-based admin would switch between the two identities on every apply.
  validation {
    condition     = length(var.admin_principal_arns) > 0 && alltrue([for arn in var.admin_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:(role|user)/", arn))])
    error_message = "Give at least one IAM role or user ARN, e.g. arn:aws:iam::123456789012:role/your-admin-role."
  }
}

variable "system_node_instance_types" {
  description = "Instance types for the system node group (Graviton: cheaper per vCPU; all add-on images are multi-arch)."
  type        = list(string)
  default     = ["t4g.medium"]
}

variable "log_retention_days" {
  description = "Retention for control-plane and VPC flow logs. Short on purpose: this cluster is torn down after every session."
  type        = number
  default     = 7
}
