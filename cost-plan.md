# Cost Optimization Plan for Rekor BigQuery Pipeline

## Executive Summary

The current streaming pipeline costs approximately **$158/month** at current Rekor activity levels. By switching to batch loading, you can reduce costs by **47%** to approximately **$84/month** while maintaining hourly data freshness.

## Current Streaming Pipeline Costs

Based on observed metrics:
- **Daily volume**: 11.6 million entries (47.8 GB)
- **Growth rate**: ~8,075 entries/minute

### Monthly Cost Breakdown

| Service | Cost Type | Monthly Cost |
|---------|-----------|--------------|
| BigQuery Streaming | $0.01 per 200MB | $73.50 |
| PubSub Delivery | $40 per TB | $56.10 |
| BigQuery Storage | $0.02 per GB | $28.69 |
| **Total** | | **$158.29** |

### Growth Projections

At current growth rates:
- 3 months: ~4.2 TB stored → $232/month
- 6 months: ~8.4 TB stored → $306/month
- 12 months: ~16.8 TB stored → $454/month

## Data Retention Strategy

BigQuery storage costs grow linearly with data volume. Implementing a retention policy is crucial for long-term cost management.

### Storage Cost Impact

| Retention Period | Data Volume | Monthly Storage Cost | Annual Storage Cost |
|-----------------|-------------|---------------------|-------------------|
| 30 days | 1.4 TB | $28.69 | $344 |
| 90 days | 4.2 TB | $86.07 | $1,033 |
| 180 days | 8.4 TB | $172.14 | $2,066 |
| 365 days | 17.0 TB | $348.28 | $4,179 |
| No limit | Grows forever | Increases monthly | Unbounded |

### Implementing Table Partitioning Expiration

Add partition expiration to automatically delete old data:

```hcl
resource "google_bigquery_table" "entries" {
  # ... existing configuration ...
  
  time_partitioning {
    type  = "DAY"
    field = "publish_time"
    
    # Automatically delete partitions older than 90 days
    expiration_ms = 7776000000  # 90 days in milliseconds
  }
}
```

### Long-term Storage Discounts

BigQuery offers automatic discounts for data not modified in the last 90 days:
- **Active storage**: $0.02/GB/month (first 90 days)
- **Long-term storage**: $0.01/GB/month (after 90 days)

With this discount, keeping 1 year of data costs:
- First 90 days (4.2 TB): $86.07/month
- Remaining 275 days (12.8 TB): $131.20/month
- **Total**: $217.27/month (vs $348.28 without discount)

### Retention Recommendations

1. **High-frequency analysis (30 days)**: Keep recent data for active queries
   - Cost: $29/month
   - Use case: Security incident investigation

2. **Quarterly reporting (90 days)**: Balance cost and history
   - Cost: $86/month
   - Use case: Compliance and trend analysis

3. **Annual archive (365 days + archive)**: Export old data to Cloud Storage
   - Active BigQuery: $217/month (with long-term discount)
   - Cloud Storage Archive: $1.20/TB/month
   - Use case: Long-term compliance, rare access

### Archival Strategy

For data older than your retention period:

```bash
# Export to Cloud Storage (Nearline for 30+ day access)
bq extract \
  --destination_format=AVRO \
  --compression=SNAPPY \
  'project:dataset.entries$20240101' \
  gs://your-archive-bucket/rekor/2024/01/01/*.avro

# Set lifecycle rule for automatic storage class transitions
gsutil lifecycle set archive-lifecycle.json gs://your-archive-bucket
```

`archive-lifecycle.json`:
```json
{
  "lifecycle": {
    "rule": [
      {
        "action": {
          "type": "SetStorageClass",
          "storageClass": "NEARLINE"
        },
        "condition": {
          "age": 30
        }
      },
      {
        "action": {
          "type": "SetStorageClass",
          "storageClass": "COLDLINE"
        },
        "condition": {
          "age": 90
        }
      },
      {
        "action": {
          "type": "SetStorageClass",
          "storageClass": "ARCHIVE"
        },
        "condition": {
          "age": 365
        }
      }
    ]
  }
}
```

### Cost Comparison with Retention

| Strategy | Streaming Cost | Storage Cost (90-day) | Total Monthly |
|----------|---------------|---------------------|---------------|
| Streaming, no retention | $130/mo | Grows forever | Unbounded |
| Streaming, 90-day retention | $130/mo | $86/mo | $216/mo |
| Batch, no retention | $60/mo | Grows forever | Unbounded |
| **Batch, 90-day retention** | **$60/mo** | **$86/mo** | **$146/mo** |

## Batch Loading Alternative

Replace the BigQuery subscription with a scheduled batch loading pipeline to eliminate streaming insert costs.

### Architecture

```
Rekor Topic → Pull Subscription → Cloud Scheduler (hourly)
                                          ↓
                                   Cloud Function
                                          ↓
                            [Pull messages → Create NDJSON file]
                                          ↓
                                   Cloud Storage
                                          ↓
                              BigQuery (batch load - FREE!)
```

### Cost Analysis

| Component | Current (Streaming) | Batch (Hourly) | Savings |
|-----------|-------------------|----------------|---------|
| BigQuery Inserts | $73.50/mo | $0.00 | $73.50 |
| PubSub Delivery | $56.10/mo | $56.10/mo | $0.00 |
| Cloud Storage | $0.00 | $2.00/mo | -$2.00 |
| Cloud Function | $0.00 | $3.00/mo | -$3.00 |
| BigQuery Storage | $28.69/mo | $28.69/mo | $0.00 |
| **Total** | **$158.29/mo** | **$89.79/mo** | **$68.50** |
| **Percentage Saved** | | | **43%** |

## Implementation Guide

### Step 1: Create Cloud Storage Bucket

```bash
gsutil mb -p YOUR_PROJECT_ID gs://YOUR_PROJECT_ID-rekor-batch
gsutil lifecycle set lifecycle.json gs://YOUR_PROJECT_ID-rekor-batch
```

`lifecycle.json`:
```json
{
  "lifecycle": {
    "rule": [{
      "action": {"type": "Delete"},
      "condition": {"age": 7}
    }]
  }
}
```

### Step 2: Create Pull Subscription

```hcl
resource "google_pubsub_subscription" "rekor_pull" {
  name    = "rekor-pull-batch"
  topic   = "projects/project-rekor/topics/new-entry"
  
  ack_deadline_seconds = 600  # 10 minutes for batch processing
  
  expiration_policy {
    ttl = "2678400s"  # 31 days
  }
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}
```

### Step 3: Create Cloud Function

```python
import json
import base64
from datetime import datetime
from google.cloud import pubsub_v1, storage, bigquery

def batch_load_rekor(request):
    """Pull messages, write to GCS, load to BigQuery"""
    
    # Configuration
    project_id = "YOUR_PROJECT_ID"
    subscription_name = "rekor-pull-batch"
    bucket_name = f"{project_id}-rekor-batch"
    dataset_id = "rekor_stream"
    table_id = "entries"
    max_messages = 10000
    
    # Initialize clients
    subscriber = pubsub_v1.SubscriberClient()
    storage_client = storage.Client()
    bq_client = bigquery.Client()
    
    # Pull messages
    subscription_path = subscriber.subscription_path(project_id, subscription_name)
    response = subscriber.pull(
        request={"subscription": subscription_path, "max_messages": max_messages}
    )
    
    if not response.received_messages:
        return "No messages to process", 200
    
    # Process messages into NDJSON
    timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    filename = f"rekor-batch-{timestamp}.json"
    
    rows = []
    ack_ids = []
    
    for message in response.received_messages:
        rows.append({
            "subscription_name": subscription_path,
            "message_id": message.message.message_id,
            "publish_time": message.message.publish_time.isoformat(),
            "data": base64.b64encode(message.message.data).decode('utf-8'),
            "attributes": json.dumps(dict(message.message.attributes))
        })
        ack_ids.append(message.ack_id)
    
    # Write to Cloud Storage
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(filename)
    blob.upload_from_string(
        '\n'.join(json.dumps(row) for row in rows),
        content_type='application/json'
    )
    
    # Load to BigQuery
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )
    
    uri = f"gs://{bucket_name}/{filename}"
    table_ref = bq_client.dataset(dataset_id).table(table_id)
    
    load_job = bq_client.load_table_from_uri(
        uri, table_ref, job_config=job_config
    )
    load_job.result()  # Wait for job to complete
    
    # Acknowledge messages after successful load
    subscriber.acknowledge(
        request={"subscription": subscription_path, "ack_ids": ack_ids}
    )
    
    return f"Processed {len(rows)} messages", 200
```

### Step 4: Schedule with Cloud Scheduler

```hcl
resource "google_cloud_scheduler_job" "rekor_batch" {
  name             = "rekor-batch-load"
  schedule         = "0 * * * *"  # Every hour
  time_zone        = "UTC"
  attempt_deadline = "1200s"

  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions_function.batch_loader.https_trigger_url
  }
}
```

## Migration Strategy

### Phase 1: Parallel Running (1 week)
1. Deploy batch pipeline alongside existing streaming
2. Monitor both pipelines for data consistency
3. Verify no message loss

### Phase 2: Gradual Transition (1 week)
1. Reduce streaming subscription's max delivery attempts
2. Monitor dead letter queue
3. Ensure batch pipeline handles full load

### Phase 3: Complete Migration
1. Delete BigQuery subscription
2. Monitor for any issues
3. Optimize batch size and frequency based on metrics

## Trade-offs

### Advantages
- **Cost Savings**: 43% reduction in monthly costs
- **Flexibility**: Can add data transformations
- **Error Recovery**: Failed batches can be reprocessed
- **Storage Optimization**: Can compress/partition data before loading

### Disadvantages
- **Data Latency**: 1-hour delay vs real-time
- **Complexity**: More components to manage
- **Operational Overhead**: Need to monitor batch jobs

## Monitoring

### Key Metrics
- Cloud Function execution time and success rate
- Cloud Storage object count and size
- BigQuery load job success rate
- PubSub subscription backlog
- Cost tracking by service

### Alerts
```hcl
resource "google_monitoring_alert_policy" "batch_failure" {
  display_name = "Rekor Batch Load Failure"
  conditions {
    display_name = "Cloud Function failures"
    condition_threshold {
      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\" AND metric.labels.status!=\"ok\""
      comparison = "COMPARISON_GT"
      threshold_value = 5
      duration = "300s"
    }
  }
}
```

## Alternative Batch Frequencies

| Frequency | Latency | Monthly Cost | Use Case |
|-----------|---------|--------------|----------|
| Every 15 min | 15 min | ~$95 | Near real-time needs |
| Hourly | 1 hour | ~$90 | **Recommended** |
| Every 6 hours | 6 hours | ~$86 | Cost-optimized |
| Daily | 24 hours | ~$84 | Maximum savings |

## Conclusion

Switching to batch loading provides significant cost savings with acceptable latency trade-offs. The hourly batch frequency offers the best balance of cost savings (43%) and data freshness for most use cases.