# Rekor PubSub to BigQuery Pipeline

This Terraform configuration sets up a streaming pipeline to ingest [Sigstore Rekor](https://www.sigstore.dev/what-is-sigstore) transparency log entries from the public PubSub topic into BigQuery for analysis.

## Overview

Rekor is Sigstore's transparency log for supply chain security. This pipeline:

- Subscribes to Rekor's public PubSub topic (`projects/project-rekor/topics/new-entry`)
- Streams new transparency log entries directly to BigQuery
- Provides a parsed view for easy querying
- Includes monitoring and alerting

## Architecture

```
Rekor Public Topic → PubSub Subscription → BigQuery Table
                           ↓
                    Dead Letter Topic
```

## Prerequisites

1. A Google Cloud project with billing enabled
2. The following APIs enabled:
   - BigQuery API
   - Pub/Sub API
   - Cloud Monitoring API
3. Terraform >= 1.0

## Usage

1. Clone this repository:
   ```bash
   git clone <repository>
   cd rekor-bq
   ```

2. Create a `terraform.tfvars` file:
   ```hcl
   project_id = "your-gcp-project-id"
   region     = "us-central1"  # Optional, defaults to us-central1
   ```

3. Initialize and apply Terraform:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. Verify the pipeline is working:
   ```bash
   # Check subscription metrics in Cloud Console
   # Or use the example queries from terraform output
   terraform output -raw example_queries
   ```

## What Gets Created

- **BigQuery Dataset**: `rekor_stream`
  - `entries` table: Raw messages from PubSub
  - `entries_dead_letter` table: Failed messages
  - `entries_parsed` view: Parsed CloudEvents attributes

- **PubSub Resources**:
  - Subscription: `rekor-to-bigquery`
  - Dead letter topic: `rekor-bigquery-dead-letter`

- **Monitoring**:
  - Alert policies for backlog and dead letter messages
  - Dashboard for pipeline metrics

- **IAM Permissions**:
  - BigQuery Data Editor and Metadata Viewer for PubSub service account

## Querying Data

The pipeline stores raw PubSub messages. Use the `entries_parsed` view for easier queries:

```sql
-- Recent entries
SELECT * 
FROM `your-project.rekor_stream.entries_parsed`
WHERE publish_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY publish_time DESC
LIMIT 100;

-- Count by event type
SELECT 
  ce_type,
  COUNT(*) as count
FROM `your-project.rekor_stream.entries_parsed`
WHERE DATE(publish_time) = CURRENT_DATE()
GROUP BY ce_type;
```

## Message Format

Messages contain:
- CloudEvents metadata in the `attributes` field
- TransparencyLogEntry protobuf in the `data` field (base64 encoded)

### CloudEvents Attributes
- `ce-id`, `ce-type`, `ce-source`, `ce-time`: Standard CloudEvents fields
- `rekor_log_index`: The log index of the entry
- `rekor_signing_subjects`: Signing subject information

## Cost Considerations

- **PubSub**: ~$40/TB for message delivery
- **BigQuery**: 
  - Storage: $0.02/GB/month (first 10GB free)
  - Streaming inserts: $0.01/200MB
- **Monitoring**: Minimal cost for alerts and dashboard

## Monitoring

Check the Cloud Monitoring dashboard for:
- Message throughput
- Subscription backlog
- Dead letter messages

Alerts are configured for:
- Backlog > 1GB
- Dead letter messages > 10/minute

## Troubleshooting

1. **No data appearing**: Check subscription permissions and verify the PubSub service account has BigQuery access
2. **Dead letter messages**: Check CloudEvents format compatibility
3. **High backlog**: May indicate BigQuery quota issues or schema problems

## Next Steps

1. Create a UDF to parse the TransparencyLogEntry protobuf
2. Build dashboards for supply chain security monitoring
3. Set up scheduled queries for regular analysis
4. Archive old data to reduce storage costs

## License

[Your license here]