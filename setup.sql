-- Create the table if it does not already exist
CREATE TABLE IF NOT EXISTS cdc_processing (
    -- Stores the last processed CDC log position
    last_processed_cdc_log_position INT DEFAULT 0
);

-- Insert an initial row only if the table is empty
-- This ensures there is at least one record to track progress
INSERT INTO cdc_processing (last_processed_cdc_log_position)
SELECT 0
WHERE NOT EXISTS (
    SELECT 1 FROM cdc_processing
);
