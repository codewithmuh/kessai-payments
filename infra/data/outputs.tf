output "db_cluster_identifier" {
  description = "Aurora cluster identifier (drill 5: aws rds failover-db-cluster --db-cluster-identifier ...)."
  value       = aws_rds_cluster.this.cluster_identifier
}

output "db_writer_endpoint" {
  description = "Cluster (writer) endpoint. After a failover it points at the new writer; clients must reconnect."
  value       = aws_rds_cluster.this.endpoint
}

output "db_reader_endpoint" {
  description = "Reader endpoint, for read-only queries such as statements and reconciliation."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager secret with the database user and password (the ExternalSecret's remote key)."
  value       = local.db_secret_arn
}

output "global_cluster_identifier" {
  description = "Aurora global cluster the Osaka secondary joins (null unless enable_global_database)."
  value       = one(aws_rds_global_cluster.this[*].global_cluster_identifier)
}

output "webhook_queue_url" {
  description = "SQS FIFO queue for webhook events (outbox-relay sends, webhook-sender receives)."
  value       = aws_sqs_queue.webhook_events.url
}

output "webhook_dlq_url" {
  description = "Dead-letter queue: events whose delivery failed webhook_max_receive_count times; replay from here."
  value       = aws_sqs_queue.webhook_events_dlq.url
}

output "settlement_bucket" {
  description = "S3 bucket for mock-bank settlement files (key prefix settlements/)."
  value       = aws_s3_bucket.settlements.id
}
