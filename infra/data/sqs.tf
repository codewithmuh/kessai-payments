# Webhook events: outbox-relay copies rows from the outbox table (in Aurora) into this queue, and
# webhook-sender delivers them to merchants, signed, with retries. After webhook_max_receive_count failed
# attempts an event moves to the dead-letter queue, from where the operator replays it (drill 2).
#
# Nothing is lost if the queue is: every event is also in Aurora's outbox and delivery tables, and the
# relay re-sends anything not marked delivered. Merchants deduplicate by event id.
#
# FIFO, one message group per merchant: a merchant receives its events in order, and a slow merchant only
# delays its own group. The relay sets MessageDeduplicationId to the event id, so a relay that crashes and
# re-sends within five minutes does not create a duplicate.
#
# Encryption: SQS-managed keys (free). Messages are short-lived copies of rows in Aurora, which is
# encrypted with the money-data key; SSE-SQS keeps producers and consumers free of KMS permissions.

resource "aws_sqs_queue" "webhook_events_dlq" {
  name                    = "${var.name}-webhook-events-dlq.fifo"
  fifo_queue              = true
  sqs_managed_sse_enabled = true

  # 14 days, the maximum: time to fix the merchant's endpoint and replay.
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "webhook_events" {
  name                    = "${var.name}-webhook-events.fifo"
  fifo_queue              = true
  sqs_managed_sse_enabled = true

  content_based_deduplication = false # the relay sets MessageDeduplicationId = event id
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId" # high-throughput FIFO: limits apply per merchant

  visibility_timeout_seconds = var.webhook_visibility_timeout_seconds
  receive_wait_time_seconds  = 20     # long polling: fewer empty receives
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.webhook_events_dlq.arn
    maxReceiveCount     = var.webhook_max_receive_count
  })
}

# Only the webhook queue may send its failures here.
resource "aws_sqs_queue_redrive_allow_policy" "webhook_events_dlq" {
  queue_url = aws_sqs_queue.webhook_events_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.webhook_events.arn]
  })
}
