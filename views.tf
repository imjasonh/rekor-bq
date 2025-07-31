# Comprehensive view that parses all available data from Rekor entries
resource "google_bigquery_table" "entries_parsed" {
  dataset_id = google_bigquery_dataset.rekor_stream.dataset_id
  table_id   = "entries_parsed"

  view {
    query = <<-SQL
      SELECT
        -- PubSub metadata
        subscription_name,
        message_id,
        publish_time,
        
        -- CloudEvents attributes
        JSON_VALUE(attributes, '$.type') as ce_type,
        JSON_VALUE(attributes, '$.source') as ce_source,
        JSON_VALUE(attributes, '$.time') as ce_time,
        JSON_VALUE(attributes, '$.datacontenttype') as ce_datacontenttype,
        JSON_VALUE(attributes, '$.rekor_entry_kind') as entry_kind,
        JSON_VALUE(attributes, '$.rekor_signing_subjects') as signing_subjects,
        
        -- CloudEvents ID and timestamp
        JSON_VALUE(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.id') as event_id,
        PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%SZ', JSON_VALUE(attributes, '$.time')) as event_timestamp,
        JSON_VALUE(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.specversion') as ce_specversion,
        JSON_VALUE(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.datacontenttype') as ce_datacontenttype_full,
        
        -- TransparencyLogEntry core fields (from nested JSON string)
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.logIndex') as log_index,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.logId.keyId') as log_id_key,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.logId.uuid') as log_id_uuid,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.kindVersion.kind') as kind,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.kindVersion.version') as version,
        CAST(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.integratedTime') AS INT64) as integrated_time_unix,
        TIMESTAMP_SECONDS(SAFE_CAST(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.integratedTime') AS INT64)) as integrated_time,
        
        -- Inclusion promise (for entries without inclusion proof yet)
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.inclusionPromise.signedEntryTimestamp') as signed_entry_timestamp,
        
        -- Inclusion proof details
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.inclusionProof.logIndex') as proof_log_index,
        CAST(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.inclusionProof.treeSize') AS INT64) as tree_size,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.inclusionProof.rootHash') as root_hash,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.inclusionProof.checkpoint.envelope') as checkpoint_envelope,
        
        -- Store arrays as JSON strings for now
        JSON_EXTRACT(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.inclusionProof.hashes') as proof_hashes_json,
        
        -- Canonicalized body
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody') as canonicalized_body_base64,
        SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))) as canonicalized_body,
        
        -- Extract commonly needed fields from canonicalized body
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.data.hash.algorithm') as hash_algorithm,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.data.hash.value') as hash_value,
        
        -- For hashedrekord entries, extract signature and public key
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.signature.content') as signature_content,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.signature.publicKey.content') as public_key_base64,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.signature.format') as signature_format,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.signature.publicKey.hint') as public_key_hint,
        
        -- For dsse entries, extract envelope hash and payload hash
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.envelopeHash.algorithm') as envelope_hash_algorithm,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.envelopeHash.value') as envelope_hash_value,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.payloadHash.algorithm') as payload_hash_algorithm,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.payloadHash.value') as payload_hash_value,
        
        -- Store dsse signatures as JSON for now
        JSON_EXTRACT(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.signatures') as dsse_signatures_json,
        
        -- For intoto entries (v0.0.2), extract the DSSE envelope content
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.content') as intoto_envelope_base64,
        
        -- Extract the full intoto envelope object for v0.0.2
        JSON_EXTRACT(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.content.envelope') as intoto_envelope_json,
        
        -- Extract envelope payload (which contains the actual attestation)
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.spec.content.envelope.payload') as intoto_payload_base64,
        
        -- Additional metadata fields
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.apiVersion') as body_api_version,
        JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(FROM_BASE64(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.canonicalizedBody')))), '$.kind') as body_kind,
        
        -- Calculate entry age for analysis
        TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), TIMESTAMP_SECONDS(SAFE_CAST(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(JSON_EXTRACT_SCALAR(SAFE.PARSE_JSON(SAFE_CONVERT_BYTES_TO_STRING(data)), '$.data')), '$.integratedTime') AS INT64)), HOUR) as entry_age_hours,
        
        -- Keep raw data for debugging
        attributes as attributes_raw,
        TO_BASE64(data) as data_base64
        
      FROM
        `${var.project_id}.${google_bigquery_dataset.rekor_stream.dataset_id}.${google_bigquery_table.entries.table_id}`
    SQL

    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.entries]
}
