# Roadmap

Built in public, phase by phase. Every phase ends with measured results, not claims. See [scope.md](scope.md).

## Phase 0: the service, locally (no AWS)

- [x] Repository from the production template: CI, scans, signed releases, Django service plumbing (probes,
      metrics, JSON logs, graceful shutdown, 503 + Retry-After during database outages)
- [ ] ADRs: money model (integer yen, double-entry), Aurora as the system of record, SQS instead of Kafka
- [ ] Payments core: wallets, ledger, idempotency keys, money rules R1–R4, concurrency and ledger tests
- [ ] Outbox → SQS → signed webhooks with retries, DLQ and replay; merchant-sim; drill 2 locally
- [ ] Daily reconciliation against a mock bank settlement file
- [ ] Payment client that logs acknowledged payments, and the lost-payment check
- [ ] Terraform for Tokyo and the backup account, and FIS templates, written and statically checked

## Phase 1: Tokyo

- [ ] EKS across three AZs, Karpenter, Argo CD, AWS Load Balancer Controller, External Secrets
- [ ] Observability: Prometheus, Grafana, OpenTelemetry; SLOs with burn-rate alerts
- [ ] Drills 1, 3, 4, 5, 12, with postmortems

## Phase 2: backups that have actually been restored

- [ ] AWS Backup for EKS and Aurora into a Vault-Locked vault in a separate account; S3 Object Lock
- [ ] Drills 6, 7, 8

## Phase 3: Osaka

- [ ] Aurora Global Database on DR days, an Osaka pilot light, Route 53 failover
- [ ] Drills 9, 10, 11

## Phase 4: v1.0

- [ ] All 11 areas of the production-grade checklist
- [ ] Case study with the measured results table
- [ ] Articles and videos
