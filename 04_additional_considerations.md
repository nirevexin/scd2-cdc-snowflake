# Additional Considerations & Recommendations

Beyond the core SCD Type 2 implementation I built with the stored procedure, I also evaluated long-term operational aspects of the solution, especially around storage efficiency and architectural alternatives.

## Optimizing storage size

The CDC staging table (`product_status_cdc`) can grow significantly over time. To keep the DWH lean while preserving the ability to reprocess data when needed, I recommend archiving older CDC records to a cheaper storage layer.  

Specifically, I would unload records older than a chosen threshold (for example, 90 or 180 days based on `change_time` or `cdc_log_position`) to S3 in **Parquet** format. 

This is exactly the pattern my current company uses with Salesforce data — we move historical raw data to S3 and query it on demand using Redshift Spectrum (or in Snowflake via External Tables). 

Parquet compression further reduces storage costs while maintaining excellent query performance.

## Data Lake / House alternatives

The same SCD Type 2 logic could be implemented directly in a Data Lake. 

**Apache Iceberg** and **Apache Hudi** are excellent modern options that bring Data Warehouse capabilities (ACID transactions, schema enforcement, SQL querying) to a Data Lake architecture on S3. 

This would give us the scalability and cost advantages of a lake while keeping the reliability of a warehouse.

Also applying **Functional Kimball** approach, instead of managing complex MERGE/UPDATE logic for SCD2, we could adopt periodic (or event-driven) snapshots of the dimensions. 

This simplifies the pipeline dramatically: we would just perform regular INSERTs of the current state rather than tracking every change with start/end timestamps.  

This snapshot-based model becomes attractive because it reduces complexity while still delivering the historical view required for analytics.

## Summary

The SCD2 solution I delivered is robust and production-ready today, but these storage optimization and lakehouse/snapshot strategies would make the overall platform more scalable and cost-effective as data volumes grow.
