# Olist Data Warehouse (Airflow + PostgreSQL)

Raw Olist e-commerce CSVs → a star schema in PostgreSQL, orchestrated by Airflow. Loads are incremental:
after the first run, only new or changed orders are processed. Prediction for future late deliveries.  

```
CSV files ──► staging ──────────► core ──────────────────────► reporting
 (raw)       (as-is snapshot)    (star schema, upserted)        (KPI views)
             Python COPY         SQL, watermark + ON CONFLICT   SQL
```


Start: docker compose up -d --build

   ```sql
   SELECT * FROM reporting.vw_monthly_sales;
   SELECT * FROM etl.vw_run_summary ORDER BY started_at DESC;   
   SELECT * FROM etl.etl_run_log ORDER BY etl_run_log_id DESC; 
   ```

## The DAG

```
load_staging >> build_dims >> build_fact >> build_reporting >> build_ml_features >> train_late_delivery_model  
```

## Incremental loading 

**Staging is a cheap snapshot** of the files. Core is never rebuilt: it is merged. This also works if the source starts delivering only new/changed rows instead of full files, because nothing in core is ever deleted by a load.  

## Machine learning  

LightGBM model.  
Late-delivery prediction (classification)  
ROC-AUC -> 0.733 (without geolocation)  
Late orders caught by the alert rule  