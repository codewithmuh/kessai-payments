# Terraform for Kessai: static checks (no AWS access) and the commands that create and destroy it in AWS.
# Run from this folder, or from the repository root with `make -C infra <target>`. Order, costs and
# teardown: README.md.
#
# The aws-* targets use the workload account and stop unless both are set and the logged-in account matches:
#   export AWS_PROFILE=kessai                  # your personal profile, never the machine's default identity
#   export KESSAI_ACCOUNT_ID=123456789012
# backup-account uses the separate backup account, with its own profile:
#   AWS_PROFILE=kessai-backup KESSAI_BACKUP_ACCOUNT_ID=210987654321 make backup-account

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

TERRAFORM ?= terraform
TFLINT ?= tflint
TRIVY ?= trivy
CHECKOV ?= checkov

KESSAI_REGION ?= ap-northeast-1
KESSAI_BACKUP_REGION ?= ap-northeast-3
CLUSTER := kessai

STACKS := bootstrap platform data fis backup-plan backup-account

# Each recipe line runs in a new shell; this loads the account guard and helpers into it.
# set -eu -o pipefail again because macOS ships GNU Make 3.81, which ignores .SHELLFLAGS.
SH := set -eu -o pipefail; source scripts/common.sh

# State buckets are per account, so bucket and region are passed at init time; no account ID is committed.
#   $(call tf_init,<stack>,<account id>,<region>)
tf_init = $(TERRAFORM) -chdir=$(1) init -input=false -backend-config=bucket=kessai-tfstate-$(2) -backend-config=region=$(3)
init_workload = $(call tf_init,$(1),$(KESSAI_ACCOUNT_ID),$(KESSAI_REGION))

.PHONY: help fmt fmt-check validate lint scan check \
  aws-guard aws-bootstrap backup-account aws-backup-plan aws-plan aws-up aws-fis aws-down aws-leftovers kubeconfig

help: ## Show available commands
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

################################################################################
# Static checks: no AWS credentials, nothing planned or applied
################################################################################

fmt: ## Format every stack
	$(TERRAFORM) fmt -recursive .

fmt-check: ## Fail if any file is not formatted
	$(TERRAFORM) fmt -check -recursive -diff .

validate: ## terraform validate every stack (init without a backend: downloads providers and modules only)
	for stack in $(STACKS); do \
	  echo "== $$stack"; \
	  $(TERRAFORM) -chdir=$$stack init -backend=false -input=false >/dev/null || exit 1; \
	  $(TERRAFORM) -chdir=$$stack validate || exit 1; \
	done

lint: ## tflint with the AWS ruleset (.tflint.hcl)
	$(TFLINT) --init
	$(TFLINT) --recursive --config "$$PWD/.tflint.hcl"

scan: ## trivy and checkov misconfiguration scans; accepted findings are suppressed next to the code
	$(TRIVY) config --skip-dirs '**/.terraform' --severity CRITICAL,HIGH --exit-code 1 .
	$(CHECKOV) -d . --config-file .checkov.yaml --quiet --compact

check: fmt-check validate lint scan ## Everything above, as CI runs it

################################################################################
# AWS: workload account
################################################################################

# Terraform's provider refuses every account except this one (allowed_account_ids), and the region
# reaches every stack as a variable.
aws-bootstrap aws-backup-plan aws-plan aws-up aws-fis aws-down: export TF_VAR_account_id = $(KESSAI_ACCOUNT_ID)
aws-bootstrap aws-backup-plan aws-plan aws-up aws-fis aws-down: export TF_VAR_region = $(KESSAI_REGION)

aws-guard:
	@$(SH); require_aws_profile; require_kessai_account
	@echo "AWS account check passed (profile $$AWS_PROFILE)."

aws-bootstrap: aws-guard ## Once per account (again when bootstrap changes): state bucket, CI roles, budgets, money-data key
	scripts/create-state-bucket.sh workload
	$(call init_workload,bootstrap)
	$(TERRAFORM) -chdir=bootstrap apply
	@echo "Next: copy the role and bucket outputs into the GitHub repository variables (README.md)."

aws-backup-plan: aws-guard ## Once, after backup-account: AWS Backup plans copying Aurora and EKS to the backup account
	@# EKS is a newer AWS Backup resource type; make sure both types are opted in for this Region.
	aws backup update-region-settings --region $(KESSAI_REGION) --resource-type-opt-in-preference Aurora=true,EKS=true
	$(call init_workload,backup-plan)
	$(TERRAFORM) -chdir=backup-plan apply

aws-plan: aws-guard ## Show what aws-up would change in the platform stack (changes nothing)
	$(call init_workload,platform)
	$(SH); cidrs=$$(api_allowed_cidrs); \
	  TF_VAR_api_allowed_cidrs="$$cidrs" $(TERRAFORM) -chdir=platform plan

aws-up: aws-guard ## Create or update platform, then data (about $0.58/hour while up); asks before each apply
	@echo 'Approximate cost while up: about $$0.58/hour (~$$4.60 per 8-hour session) before Karpenter nodes'
	@echo 'and data transfer. Stop paying: make aws-down.'
	$(call init_workload,platform)
	$(SH); cidrs=$$(api_allowed_cidrs); \
	  TF_VAR_api_allowed_cidrs="$$cidrs" $(TERRAFORM) -chdir=platform apply
	$(call init_workload,data)
	$(TERRAFORM) -chdir=data apply

aws-fis: aws-guard ## Create the FIS drill templates (after the app and its load balancer are up)
	$(call init_workload,fis)
	$(TERRAFORM) -chdir=fis apply

aws-down: aws-guard ## Destroy fis, then what Kubernetes created, then data and platform; check nothing is left
	@# 1. Drill templates, if any. -refresh=false: their lookups (e.g. the load balancer) may already be gone.
	$(call init_workload,fis)
	if [ -n "$$($(TERRAFORM) -chdir=fis state list)" ]; then \
	  $(TERRAFORM) -chdir=fis destroy -refresh=false; \
	fi
	@# 2. Load balancers, volumes and nodes that controllers made, while the cluster still exists.
	scripts/pre-destroy.sh
	@# 3. Aurora: lift deletion protection in a visible apply, then destroy (a final snapshot is kept).
	@#    The apply only runs for a cluster that exists: an apply on an empty state would create one.
	$(call init_workload,data)
	if $(TERRAFORM) -chdir=data state list | grep -x 'aws_rds_cluster.this' >/dev/null; then \
	  $(TERRAFORM) -chdir=data apply -var deletion_protection=false; \
	fi
	if [ -n "$$($(TERRAFORM) -chdir=data state list)" ]; then \
	  $(TERRAFORM) -chdir=data destroy -var deletion_protection=false; \
	fi
	@# 4. The cluster and the network.
	$(call init_workload,platform)
	$(SH); cidrs=$$(api_allowed_cidrs); \
	  TF_VAR_api_allowed_cidrs="$$cidrs" $(TERRAFORM) -chdir=platform destroy
	scripts/check-leftovers.sh

aws-leftovers: aws-guard ## List anything billable left in the region (exit 1 if there is)
	scripts/check-leftovers.sh

kubeconfig: aws-guard ## Add the EKS cluster to ~/.kube/config as context "kessai"
	aws eks update-kubeconfig --region $(KESSAI_REGION) --name $(CLUSTER) --alias $(CLUSTER)

################################################################################
# AWS: backup account (its own AWS_PROFILE and KESSAI_BACKUP_ACCOUNT_ID)
################################################################################

backup-account: export TF_VAR_backup_account_id = $(KESSAI_BACKUP_ACCOUNT_ID)
backup-account: export TF_VAR_region = $(KESSAI_BACKUP_REGION)

backup-account: ## Once, in the backup account: its state bucket, then the locked vault and Object Lock bucket in Osaka
	@$(SH); require_aws_profile; require_backup_account
	scripts/create-state-bucket.sh backup
	$(call tf_init,backup-account,$(KESSAI_BACKUP_ACCOUNT_ID),$(KESSAI_BACKUP_REGION))
	$(TERRAFORM) -chdir=backup-account apply
	@echo "Next: put output backup_vault_arn into backup-plan/terraform.tfvars, then make aws-backup-plan."
