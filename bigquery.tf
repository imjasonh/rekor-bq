resource "google_bigquery_dataset" "rekor_stream" {
  dataset_id                 = "rekor_stream"
  friendly_name              = "Rekor Transparency Log Stream"
  description                = "Streaming data from Sigstore Rekor transparency log"
  location                   = var.dataset_location
  delete_contents_on_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_bigquery_table" "entries" {
  dataset_id = google_bigquery_dataset.rekor_stream.dataset_id
  table_id   = "entries"

  time_partitioning {
    type  = "DAY"
    field = "publish_time"
  }

  clustering = ["subscription_name"]

  schema = jsonencode([
    {
      name        = "subscription_name"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Subscription that delivered this message"
    },
    {
      name        = "message_id"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "PubSub message ID"
    },
    {
      name        = "publish_time"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "PubSub publish time"
    },
    {
      name        = "data"
      type        = "BYTES"
      mode        = "NULLABLE"
      description = "TransparencyLogEntry protobuf (base64)"
    },
    {
      name        = "attributes"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "CloudEvents attributes as JSON string"
    }
  ])

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_bigquery_table" "entries_dead_letter" {
  dataset_id = google_bigquery_dataset.rekor_stream.dataset_id
  table_id   = "entries_dead_letter"

  schema = jsonencode([
    {
      name = "subscription_name"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "message_id"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "publish_time"
      type = "TIMESTAMP"
      mode = "NULLABLE"
    },
    {
      name = "data"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "attributes"
      type = "STRING"
      mode = "NULLABLE"
    }
  ])
}