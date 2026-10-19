variable "account_id" {
  description = "The AWS account Kessai runs in (the workload account). The provider refuses every other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region. Must match infra/platform and infra/data."
  type        = string
  default     = "ap-northeast-1"
}

variable "name" {
  description = "Name of the platform the drills target (cluster, VPC, Aurora cluster) and prefix of the FIS roles."
  type        = string
  default     = "kessai"

  validation {
    condition     = var.name == "kessai" || startswith(var.name, "kessai-")
    error_message = "name must be \"kessai\" or start with \"kessai-\", or the CI apply role cannot create its IAM roles."
  }
}

variable "environment" {
  description = "Environment tag."
  type        = string
  default     = "dev"
}

variable "alb_name" {
  description = "Name of the API's load balancer, fixed by the Ingress annotation alb.ingress.kubernetes.io/load-balancer-name. Its 5xx rate is the stop condition of every drill."
  type        = string
  default     = "kessai-api"
}

variable "log_retention_days" {
  description = "Retention of the FIS experiment logs (each drill's timeline for the postmortem)."
  type        = number
  default     = 30
}

################################################################################
# Stop condition
################################################################################

variable "stop_error_rate_percent" {
  description = "Stop a drill when more than this share of API requests fail with 5xx..."
  type        = number
  default     = 20
}

variable "stop_after_minutes" {
  description = "...for this many minutes in a row. The pass target is < 1% errors for < 2 minutes, so this means the system is not recovering."
  type        = number
  default     = 3
}

################################################################################
# Drill 1: pod delete
################################################################################

variable "app_namespace" {
  description = "Kubernetes namespace of the Kessai workloads."
  type        = string
  default     = "kessai"
}

variable "fis_kubernetes_name" {
  description = "Kubernetes user the FIS role maps to (access entry) and service account the FIS pod runs as. Both are bound to the RBAC Role in infra/README.md."
  type        = string
  default     = "fis-experiment"
}

variable "api_pod_selector" {
  description = "Label selector of the API pods."
  type        = string
  default     = "app.kubernetes.io/name=kessai-api"
}

variable "api_pod_selection" {
  description = "How many API pods to kill at once. COUNT(2) of 3 leaves one serving."
  type        = string
  default     = "COUNT(2)"
}

variable "worker_pod_selector" {
  description = "Label selector of the worker pods (outbox-relay and webhook-sender)."
  type        = string
  default     = "app.kubernetes.io/component=worker"
}

variable "worker_pod_selection" {
  description = "How many worker pods to kill. ALL: every relay and sender restarts at once, the worst case for duplicate deliveries."
  type        = string
  default     = "ALL"
}

################################################################################
# Drill 4: AZ power interruption
################################################################################

variable "impaired_az_id" {
  description = "Zone ID of the AZ to take out. apne1-az4 replays the 2019 Tokyo outage and, with infra/platform's defaults, also holds the single NAT gateway."
  type        = string
  default     = "apne1-az4"
}

variable "az_impairment_minutes" {
  description = "How long the AZ stays down. AWS's scenario uses 30; 10 keeps a run near $4 (FIS bills $0.10 per action-minute)."
  type        = number
  default     = 10

  validation {
    condition     = var.az_impairment_minutes >= 3 && var.az_impairment_minutes <= 30
    error_message = "Use 3 to 30 minutes."
  }
}

variable "network_disruption_minutes" {
  description = "How long all traffic in and out of the AZ's subnets is dropped (the scenario's 2 minutes, while DNS still points at the AZ). Zonal shift starts when it ends."
  type        = number
  default     = 2

  validation {
    condition     = var.network_disruption_minutes >= 1 && var.network_disruption_minutes < var.az_impairment_minutes
    error_message = "network_disruption_minutes must be at least 1 and shorter than az_impairment_minutes."
  }
}
