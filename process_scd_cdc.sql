CREATE OR REPLACE PROCEDURE process_scd_cdc(p_cdc_log_position NUMBER DEFAULT 0)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_last_pos NUMBER DEFAULT p_cdc_log_position;
BEGIN
    -- 1. Full reprocess
    IF (v_last_pos = 0) THEN
        TRUNCATE TABLE product_status_hst;
    END IF;

    -- 2. New CDC records - Deduplication with DISTINCT 
    CREATE OR REPLACE TEMP TABLE new_cdc AS
    SELECT DISTINCT
        product_key,
        status,
        PARSE_JSON(change_type):type::STRING AS change_type,
        change_time,
        cdc_log_position
    FROM product_status_cdc
    WHERE cdc_log_position > v_last_pos;

    IF ((SELECT COUNT(*) FROM new_cdc) = 0) THEN
        RETURN 'No new CDC records to process.';
    END IF;

    -- 3. Affected products
    CREATE OR REPLACE TEMP TABLE affected_products AS
        SELECT DISTINCT product_key FROM new_cdc;

    -- 4. Delete old SCD rows for affected products (idempotent & safe)
    DELETE FROM product_status_hst
    WHERE product_status_product_key IN (SELECT product_key FROM affected_products);

    -- 5. Recompute FULL history for affected products only
    CREATE OR REPLACE TEMP TABLE flagged AS
    WITH ordered_cdc AS (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY product_key ORDER BY change_time, cdc_log_position) AS seq
        FROM product_status_cdc
        WHERE product_key IN (SELECT product_key FROM affected_products)
        QUALIFY ROW_NUMBER() OVER (PARTITION BY product_key, status, change_type, change_time, cdc_log_position) = 1
    )
    SELECT
        product_key,
        status,
        change_type,
        change_time,
        LAG(status)      OVER (PARTITION BY product_key ORDER BY change_time, cdc_log_position) AS prev_status,
        LAG(change_type) OVER (PARTITION BY product_key ORDER BY change_time, cdc_log_position) AS prev_change_type
    FROM ordered_cdc;

    -- 6. Version start events
    CREATE OR REPLACE TEMP TABLE version_starts AS
    SELECT
        product_key,
        status,
        change_time AS scd_start_time
    FROM flagged
    WHERE change_type = 'INSERT'
       OR (change_type = 'UPDATE' AND (
               prev_status IS NULL 
            OR status != prev_status 
            OR prev_change_type = 'DELETE'
       ));

    -- 7. Final SCD2 using MERGE (modern Snowflake pattern)
    MERGE INTO product_status_hst AS tgt
    USING (
        SELECT
            s.product_key                               AS product_status_product_key,
            s.status                                    AS product_status_status,
            s.scd_start_time,
            COALESCE(MIN(c.close_time), '2999-01-01 00:00:00'::TIMESTAMP) AS scd_end_time
        FROM version_starts s
        LEFT JOIN (
            SELECT 
                product_key, 
                change_time AS close_time
            FROM flagged
            WHERE change_type = 'DELETE'
               OR (change_type = 'UPDATE' AND status != prev_status)   -- ← FIXED
        ) c
          ON s.product_key = c.product_key
         AND c.close_time > s.scd_start_time
        GROUP BY s.product_key, s.status, s.scd_start_time
    ) AS src
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (
            product_status_product_key,
            product_status_status,
            scd_start_time,
            scd_end_time
        )
        VALUES (
            src.product_status_product_key,
            src.product_status_status,
            src.scd_start_time,
            src.scd_end_time
        );

    -- 8. Update last processed position
    UPDATE cdc_processing
    SET last_processed_cdc_log_position = (SELECT MAX(cdc_log_position) FROM new_cdc);

    RETURN 'SCD Type 2 processed successfully (DISTINCT dedup + MERGE).';
END;
$$;
