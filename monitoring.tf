# Alert for high subscription backlog
resource "google_monitoring_alert_policy" "subscription_backlog" {
  display_name = "Rekor BigQuery Subscription Backlog"
  combiner     = "OR"

  conditions {
    display_name = "Subscription backlog too high"

    condition_threshold {
      filter          = "resource.type=\"pubsub_subscription\" AND resource.labels.subscription_id=\"${google_pubsub_subscription.rekor_to_bigquery.name}\" AND metric.type=\"pubsub.googleapis.com/subscription/backlog_bytes\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1000000000 # 1GB

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  documentation {
    content = "The Rekor BigQuery subscription has a backlog greater than 1GB. This may indicate issues with BigQuery ingestion."
  }
}

# Alert for dead letter messages
resource "google_monitoring_alert_policy" "dead_letter_messages" {
  display_name = "Rekor BigQuery Dead Letter Messages"
  combiner     = "OR"

  conditions {
    display_name = "Dead letter messages detected"

    condition_threshold {
      filter          = "resource.type=\"pubsub_subscription\" AND resource.labels.subscription_id=\"${google_pubsub_subscription.rekor_to_bigquery.name}\" AND metric.type=\"pubsub.googleapis.com/subscription/dead_letter_message_count\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  documentation {
    content = "Messages are being sent to the dead letter topic. Check BigQuery table schema compatibility and message format."
  }
}

# Dashboard for monitoring
resource "google_monitoring_dashboard" "rekor_bigquery" {
  dashboard_json = jsonencode({
    displayName = "Rekor BigQuery Pipeline"
    gridLayout = {
      widgets = [
        {
          title = "Message Throughput"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"pubsub_subscription\" AND resource.labels.subscription_id=\"${google_pubsub_subscription.rekor_to_bigquery.name}\" AND metric.type=\"pubsub.googleapis.com/subscription/ack_message_count\""
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Subscription Backlog"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"pubsub_subscription\" AND resource.labels.subscription_id=\"${google_pubsub_subscription.rekor_to_bigquery.name}\" AND metric.type=\"pubsub.googleapis.com/subscription/backlog_bytes\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Dead Letter Messages"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"pubsub_subscription\" AND resource.labels.subscription_id=\"${google_pubsub_subscription.rekor_to_bigquery.name}\" AND metric.type=\"pubsub.googleapis.com/subscription/dead_letter_message_count\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        }
      ]
    }
  })
}