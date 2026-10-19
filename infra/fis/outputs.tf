output "start_drill_01" {
  description = "Starts drill 1 (pod delete)."
  value       = "aws fis start-experiment --region ${var.region} --experiment-template-id ${aws_fis_experiment_template.pod_delete.id}"
}

output "start_drill_04" {
  description = "Starts drill 4 (AZ power interruption)."
  value       = "aws fis start-experiment --region ${var.region} --experiment-template-id ${aws_fis_experiment_template.az_power.id}"
}

output "start_drill_05" {
  description = "Starts drill 5 (Aurora failover)."
  value       = "aws fis start-experiment --region ${var.region} --experiment-template-id ${aws_fis_experiment_template.db_failover.id}"
}

output "impaired_az" {
  description = "The AZ drill 4 takes out, by ID and by this account's name for it."
  value       = "${var.impaired_az_id} (${data.aws_availability_zone.impaired.name})"
}

output "experiment_log_group" {
  description = "CloudWatch log group with this session's experiment timelines (kept after destroy, expires on its own)."
  value       = aws_cloudwatch_log_group.fis.name
}
