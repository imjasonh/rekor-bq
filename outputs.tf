output "project_number" {
  description = "The project number (auto-discovered)"
  value       = data.google_project.project.number
}

output "dataset_id" {
  description = "The ID of the BigQuery dataset"
  value       = google_bigquery_dataset.rekor_stream.dataset_id
}

output "table_id" {
  description = "The ID of the main entries table"
  value       = google_bigquery_table.entries.table_id
}

output "subscription_name" {
  description = "The name of the PubSub subscription"
  value       = google_pubsub_subscription.rekor_to_bigquery.name
}

output "dead_letter_topic" {
  description = "The name of the dead letter topic"
  value       = google_pubsub_topic.rekor_dead_letter.name
}

output "parsed_view_id" {
  description = "The ID of the parsed entries view"
  value       = google_bigquery_table.entries_parsed_view.table_id
}

output "dashboard_id" {
  description = "The ID of the monitoring dashboard"
  value       = google_monitoring_dashboard.rekor_bigquery.id
}

output "example_queries" {
  description = "Example BigQuery queries to get started"
  value = {
    recent_entries = <<-SQL
      SELECT * 
      FROM `${var.project_id}.${google_bigquery_dataset.rekor_stream.dataset_id}.${google_bigquery_table.entries_parsed_view.table_id}`
      WHERE publish_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
      ORDER BY publish_time DESC
      LIMIT 100
    SQL

    entries_by_type = <<-SQL
      SELECT 
        JSON_VALUE(attributes, '$.ce-type') as event_type,
        COUNT(*) as count
      FROM `${var.project_id}.${google_bigquery_dataset.rekor_stream.dataset_id}.${google_bigquery_table.entries.table_id}`
      WHERE publish_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
      GROUP BY event_type
    SQL
  }
}