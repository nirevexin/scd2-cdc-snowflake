```sql
-- Run once
CREATE TABLE IF NOT EXISTS cdc_processing (
    last_processed_cdc_log_position INT DEFAULT 0
);

-- Insert initial value if table was empty
INSERT INTO cdc_processing (last_processed_cdc_log_position)
SELECT 0
WHERE NOT EXISTS (SELECT 1 FROM cdc_processing);
