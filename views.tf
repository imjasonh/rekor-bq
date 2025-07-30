# SQL view to parse CloudEvents attributes
resource "google_bigquery_table" "entries_parsed_view" {
  dataset_id = google_bigquery_dataset.rekor_stream.dataset_id
  table_id   = "entries_parsed"

  view {
    query = <<-SQL
      SELECT
        subscription_name,
        message_id,
        publish_time,
        
        -- CloudEvents attributes (parsed from JSON string)
        JSON_VALUE(attributes, '$.ce-id') as ce_id,
        JSON_VALUE(attributes, '$.ce-type') as ce_type,
        JSON_VALUE(attributes, '$.ce-source') as ce_source,
        JSON_VALUE(attributes, '$.ce-time') as ce_time,
        JSON_VALUE(attributes, '$.ce-specversion') as ce_specversion,
        
        -- Rekor-specific attributes
        JSON_VALUE(attributes, '$.rekor_log_index') as rekor_log_index,
        JSON_VALUE(attributes, '$.rekor_log_id') as rekor_log_id,
        JSON_VALUE(attributes, '$.rekor_signing_subjects') as rekor_signing_subjects,
        
        -- Raw data for future parsing (TransparencyLogEntry protobuf)
        TO_BASE64(data) as data_base64,
        
        -- Attempt to extract basic fields if possible
        SAFE_CAST(JSON_VALUE(attributes, '$.rekor_log_index') AS INT64) as log_index,
        SAFE.TIMESTAMP_SECONDS(SAFE_CAST(JSON_VALUE(attributes, '$.rekor_integrated_time') AS INT64)) as integrated_time,
        
        -- Full attributes for debugging
        attributes as attributes_json
      FROM
        `${var.project_id}.${google_bigquery_dataset.rekor_stream.dataset_id}.${google_bigquery_table.entries.table_id}`
    SQL

    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.entries]
}