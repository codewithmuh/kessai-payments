# Scope

Kessai (決済, "payment") is a small wallet payments API, the kind PayPay, Merpay and Stripe run. It is deployed on
Amazon EKS in Tokyo with a disaster-recovery copy in Osaka, then broken on purpose to prove, with measured numbers,
that it never loses a payment and never charges twice.

- **It is** a reference payments service that follows real-world rules: whole-yen amounts, idempotency keys,
  signed webhooks, double-entry bookkeeping and daily reconciliation. It runs on a production-grade AWS setup and
  goes through 12 measured failure drills.
- **It is not** a payment provider. There is no real money, no card numbers (PCI DSS is out of scope) and no KYC.

## Why payments

Losing a payment, or charging one twice, is the clearest data-loss failure there is. That makes every drill
meaningful: "0 payments lost" needs no explanation. The rules are well known and public (Stripe's API, Japanese
tax and financial guidance), so the service can follow real ones instead of invented ones.

## The product

| Actor | Does |
|---|---|
| Customer | Has a wallet: tops it up, pays merchants |
| Merchant | Gets paid, refunds, receives webhooks |
| Operator | Runs reconciliation, replays events |

1. **Top up:** a customer adds money from a mock bank account.
2. **Pay:** a customer pays a merchant from the wallet balance, in one step like a QR payment. The payment
   records its tax breakdown by rate (10% standard, 8% reduced), as on a Japanese qualified invoice
   (インボイス制度, since 2023-10-01). Check the exact rounding rule (端数処理) in the National Tax Agency
   guidance before coding it.
3. **Refund:** a merchant refunds all or part of a payment.
4. **Balance and statement:** read a wallet's balance and its ledger lines.
5. **Webhooks:** merchants receive `payment.succeeded` and `refund.succeeded`, signed, retried and replayable.
6. **Daily reconciliation:** the ledger is checked against the mock bank's settlement file.

**API (v1):**
- Money endpoints: `POST /v1/topups`, `POST /v1/payments`, `POST /v1/refunds`, each requiring an `Idempotency-Key`
  header.
- Reads: `GET /v1/payments/{id}`, `GET /v1/wallets/{id}`, and `GET /v1/events?since=` for catch-up.
- Auth: API keys (stored hashed) for merchants and demo customers.

**Not in v1:** authorise-then-capture, platform fees, merchant payouts, other currencies.

## Money rules

Every test and every drill checks these.

| # | Rule | Enforced by |
|---|---|---|
| R1 | Amounts are integer yen. No floats anywhere. | JPY has no minor unit ([Stripe: zero-decimal currencies](https://docs.stripe.com/currencies#zero-decimal)); integer columns; floats banned in the money code |
| R2 | Double-entry: every money movement writes balanced entries; all entries always sum to 0. | Entries written in the same transaction as the movement; checked in tests and after every drill |
| R3 | A wallet never goes below ¥0. | Row lock or conditional update in the same transaction; a test fires 200 parallel payments at a balance that covers 50 |
| R4 | One key, one payment. The same key and body replays the saved response. The same key with a different body is an error. Keys are kept 24 h. | Key stored in the same transaction as the payment ([Stripe: idempotent requests](https://docs.stripe.com/api/idempotent_requests)) |
| R5 | No acknowledged payment is lost when a pod, node or AZ fails. | Aurora Multi-AZ; measured by the client log (below) |
| R6 | Every payment creates exactly one event, delivered at least once; merchants deduplicate by event id. | Transactional outbox + a delivery table in the database ([Stripe: webhooks](https://docs.stripe.com/webhooks)) |
| R7 | The ledger matches the bank. | Daily reconciliation job; any difference raises an alert |

## Architecture

```
 Payment client (k6 / Python), OUTSIDE AWS → logs every acknowledged payment to a local file
        │  HTTPS
 Route 53 failover record + health check (failing over is a human decision, logged)
        │
 TOKYO ap-northeast-1 — apne1-az1 / az2 / az4                       OSAKA ap-northeast-3 (DR, pilot light)
 ALB (AWS Load Balancer Controller, readiness gate, zonal shift)     DR days only: EKS cluster synced by
 EKS (Karpenter, EC2 nodes)                                          Argo CD, Aurora Global DB secondary
   api            Deployment ≥3 pods, spread over 3 AZs, PDB         Always on: KMS multi-Region key,
   outbox-relay   Deployment: outbox rows → SQS FIFO                 ECR + Secrets Manager replicas
   webhook-sender Deployment: SQS → signed webhooks, retries → DLQ
   reconcile      CronJob (daily) + mock-bank settlement files in S3
   merchant-sim   receives webhooks, deduplicates, counts (test harness)
 Aurora PostgreSQL writer + reader (different AZs) ════ Global DB ════►  Osaka secondary
   ↑ the ONLY system of record: payments, ledger, idempotency keys, outbox, deliveries
 Backup account (separate AWS account, Osaka): AWS Backup vault with Vault Lock, S3 Object Lock
 FIS experiment templates · Prometheus / Grafana / OpenTelemetry · SLO burn-rate alerts
```

The design has one Django codebase, three Deployments, one CronJob and one database, with no Kafka and no Redis in
v1. Everything that must not be lost lives in Aurora, so "where can data be lost?" has one answer.

The outbox and the delivery table replicate to Osaka with the payments. If Tokyo is lost, the events still in
Tokyo's SQS queue don't matter: the Osaka relay re-sends every event the delivery table hasn't marked as delivered,
and merchants deduplicate by event id.

## How "no data lost" is measured

1. The payment client runs **outside AWS**. It sends payments with a client sequence number and an idempotency key.
2. It appends every **acknowledged** payment (HTTP 201) to a local file.
3. After a drill, a check compares that file with the database:
   - **lost payments** = acknowledged but missing;
   - **RPO** = that count, plus the time span it covers;
   - **RTO** = from fault injection to the first acknowledged payment through the public endpoint, split into
     database promotion, DNS and pod readiness.
4. The money rules are checked again.

## Recovery targets

These are design targets, not results.

| Data | Failure | RPO target | RTO target | Mechanism |
|---|---|---|---|---|
| Payments, ledger, keys, outbox | Pod, node or AZ loss | 0 acknowledged payments lost | DB writer ≤ 60 s; API errors < 1% for < 2 min | Aurora Multi-AZ, spread + PDBs, idempotent retries |
| Same | Tokyo region loss | ≤ 1 min, and every lost payment recovered from the failover snapshot | ≤ 30 min (pilot light) | Aurora Global Database, Argo CD, Route 53 failover |
| Same | Bad delete or corruption | ≤ 5 min | ≤ 60 min | Aurora point-in-time restore |
| Webhook events | Any of the above | 0 (re-sent from the database) | Minutes | Outbox + delivery table |
| Cluster state | Cluster lost | Last Git commit / backup | ≤ 30 min | Argo CD + AWS Backup for EKS (vs Velero) |

## The 12 drills

| # | Drill (real incident it models) | Injected with | Pass target |
|---|---|---|---|
| 1 | Kill API and worker pods mid-traffic | FIS `aws:eks:pod-delete` | 0 lost; no duplicate effects at the merchant |
| 2 | Merchant endpoint down for 30 min | merchant-sim returns 503 | Retries, DLQ, replay: every event takes effect once |
| 3 | Deploy, node drain and EKS upgrade under load | rollout restart, Karpenter consolidation, version upgrade | 0 non-2xx responses |
| 4 | Lose a Tokyo AZ (the 2019 apne1-az4 cooling failure) | FIS AZ Power Interruption (shortened) + zonal autoshift; a gray-failure variant | 0 lost; errors < 1% for < 2 min; no new nodes needed |
| 5 | Database failover while clients retry the same key | FIS `aws:rds:failover-db-cluster` + same-key retries | 0 lost; one payment per key; writer back ≤ 60 s |
| 6 | Someone runs `DELETE` on the ledger | Aurora point-in-time restore, then reconcile | RPO ≤ 5 min, RTO ≤ 60 min, ledger sums to 0 |
| 7 | Whole cluster lost | Argo CD + AWS Backup for EKS (vs Velero) | ≤ 30 min |
| 8 | Ransomware tries to delete the backups (Askul 2025) | Prod-account admin role tries to delete recovery points | 0 recovery points deleted; restore time measured |
| 9 | Planned move to Osaka | Aurora Global switchover + Argo CD + Route 53 | RPO 0; ≤ 30 min end to end |
| 10 | Tokyo region "lost" | FIS cross-region connectivity, then an unplanned global failover | Lost payments counted, then all recovered from the snapshot; ≤ 30 min |
| 11 | One bad release breaks both regions (Zengin 2023) | Promote a broken config | Osaka never receives it; rollback to the last good version |
| 12 | Month-end peak with a batch job running (Mizuho 2021) | k6 at 3–5× load + reconciliation running | Payment SLO holds; the batch job slows down instead |

Each drill gets a runbook, a results row (failure, expected, measured) and a postmortem in COE (Correction of Error)
format: impact, timeline, metrics, 5 Whys, and action items with owners and dates.

## Cost

Prices are AWS Tokyo On-Demand, checked in October 2026. This is an estimate, not a quote.

| Session | Approximate cost |
|---|---|
| Tokyo session | $0.45–0.58/h, about $4–5 for 8 hours |
| Osaka DR day | $9–12. The Global Database needs r-class instances, so it exists only on DR days |
| AWS FIS | $0.10 per action-minute; runs are kept short |
| Whole project | Roughly $150–250 if it only runs while being worked on |

Not used: ARC routing control ($2.50/h). Route 53 health checks cover the failover instead.
