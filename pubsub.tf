# Dead letter topic for failed messages
resource "google_pubsub_topic" "rekor_dead_letter" {
  name = "rekor-bigquery-dead-letter"

  message_retention_duration = "604800s" # 7 days
}

# BigQuery subscription to Rekor's public topic
resource "google_pubsub_subscription" "rekor_to_bigquery" {
  name    = "rekor-to-bigquery"
  project = var.project_id

  # Cross-project topic reference
  topic = "projects/project-rekor/topics/new-entry"

  bigquery_config {
    table = "${var.project_id}.${google_bigquery_dataset.rekor_stream.dataset_id}.${google_bigquery_table.entries.table_id}"

    # Write all message metadata
    write_metadata = true

    # Don't use topic schema (we'll handle raw protobuf)
    use_topic_schema = false
    use_table_schema = false
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.rekor_dead_letter.id
    max_delivery_attempts = 5
  }

  # Subscription expires after 31 days of inactivity
  expiration_policy {
    ttl = "2678400s"
  }

  # Retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Message retention
  message_retention_duration = "604800s" # 7 days

  # Acknowledgment deadline
  ack_deadline_seconds = 60

  depends_on = [
    google_project_iam_member.pubsub_bigquery_editor,
    google_project_iam_member.pubsub_bigquery_metadata_viewer
  ]
}