# Olist Data Warehouse (Airflow + PostgreSQL)

A small project: raw Olist e-commerce CSVs → a star schema in PostgreSQL, orchestrated by Airflow. Loads are incremental:
after the first run, only new or changed orders are processed.

```
CSV files ──► staging ──────────► core ──────────────────────► reporting
 (raw)       (as-is snapshot)    (star schema, upserted)        (KPI views)
             Python COPY         SQL, watermark + ON CONFLICT   SQL
```


Start: docker compose up -d


   ```sql
   SELECT * FROM reporting.vw_monthly_sales;
   SELECT * FROM etl.vw_run_summary ORDER BY started_at DESC;   
   SELECT * FROM etl.etl_run_log ORDER BY etl_run_log_id DESC; 
   ```

## The DAG

```
load_staging >> build_dims >> build_fact >> build_reporting
```

## Incremental loading

**Staging is a cheap snapshot** of the files. Core is never rebuilt: it is merged. This also works if the source starts delivering only new/changed rows instead of full files, because nothing in core is ever deleted by a load.