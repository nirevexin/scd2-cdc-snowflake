-- 1. Only one active record per product
SELECT product_status_product_key, COUNT(*) 
FROM product_status_hst 
WHERE scd_end_time = '2999-01-01 00:00:00'
GROUP BY product_status_product_key 
HAVING COUNT(*) > 1;

-- 2. No gaps/overlaps (consecutive periods)
WITH intervals AS (
    SELECT product_status_product_key,
           scd_start_time,
           scd_end_time,
           LAG(scd_end_time) OVER (PARTITION BY product_status_product_key ORDER BY scd_start_time) AS prev_end
    FROM product_status_hst
)
SELECT * FROM intervals
WHERE prev_end IS NOT NULL 
  AND scd_start_time != prev_end;

-- 3. Every SCD record must exist in CDC (accuracy)
WITH clean_cdc AS (
    SELECT product_key, status, MIN(change_time) AS first_change_time
    FROM product_status_cdc
    GROUP BY product_key, status
)
SELECT d.* 
FROM clean_cdc d
LEFT JOIN product_status_hst s 
       ON d.product_key = s.product_status_product_key 
      AND d.status = s.product_status_status
WHERE s.product_status_product_key IS NULL;

-- 4. Active SCD record matches latest non-deleted CDC state
WITH latest_cdc AS (
    SELECT product_key, status, MAX(change_time) AS latest_change_time
    FROM product_status_cdc
    WHERE PARSE_JSON(change_type):type::STRING != 'DELETE'
    GROUP BY product_key, status
),
active_scd AS (
    SELECT product_status_product_key, product_status_status, scd_start_time
    FROM product_status_hst
    WHERE scd_end_time = '2999-01-01 00:00:00'
)
SELECT * FROM latest_cdc l
JOIN active_scd a ON l.product_key = a.product_status_product_key
WHERE l.latest_change_time != a.scd_start_time OR l.status != a.product_status_status;
