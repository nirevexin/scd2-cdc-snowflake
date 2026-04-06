# SCD Type 2 Dimension from CDC Source (Snowflake)

Robust implementation of a Slowly Changing Dimension Type 2 (`product_status_hst`) from a Change Data Capture (CDC) source (`product_status_cdc`).

## Repository Structure

```
scd2-cdc-snowflake/
├── 01_setup.sql
├── 02_process_scd_cdc.sql ← Main stored procedure
├── 03_data_quality_checks.sql
├── 04_additional_considerations.md
├── LICENSE
└── README.md
```

## Technologies

- Snowflake (SQL + Stored Procedure)
- Designed to be easily converted to dbt (company’s production stack)

## Features & Requirements Fulfilled

- Full reprocess (no parameter) **or** incremental from a specific `cdc_log_position`
- Idempotent & supports at-least-once semantics (deduplication)
- Handles **all** edge cases listed in the assignment:
  - Duplicate identical CDC records
  - No-op UPDATEs (same status)
  - Multiple INSERTs for the same product (insert → delete → insert …)
  - Gaps in the change history
  - Ordered processing (CDC always arrives in commit order)
- Set-based SQL (no loops/cursors) → efficient and maintainable
- Uses a stored procedure for clean orchestration

## Solution Approach (Step-by-Step)

1. **Deduplication** – exact duplicate CDC records are removed.
2. **Affected products detection** – only products touched by new CDC records are recomputed.
3. **Full history recompute for affected products** – guarantees correctness even after gaps or reprocessing.
4. **Version logic**:
   - **Start events**: `INSERT` or `UPDATE` that actually changes status (or follows a `DELETE`).
   - **Close events**: `DELETE` or status-changing `UPDATE`.
   - End time = earliest future close event (or `2999-01-01 00:00:00`).
5. **Incremental safety** – old SCD rows for affected products are deleted before recomputing.

This pattern is the industry-standard way to maintain SCD2 from CDC while remaining fully idempotent.

## How to Run

```sql
-- Full reprocess
CALL process_scd_cdc(0);

-- Incremental (after a specific log position)
CALL process_scd_cdc(5);
```

## Author
Alexey Vershinin Dudin \
Data Engineer | Data Analyst
