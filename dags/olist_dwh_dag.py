"""
Olist data warehouse pipeline

    load_staging >> build_dims >> build_fact >> build_reporting

"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.models.param import Param
from airflow.operators.python import PythonOperator
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook

log = logging.getLogger(__name__)

WAREHOUSE_CONN_ID = "warehouse_db"  


PROJECT_DIR = Path(__file__).resolve().parents[1]
SQL_DIR = PROJECT_DIR / "sql"
RAW_DIR = PROJECT_DIR / "data" / "raw"

CSV_TO_STAGING_TABLE = {
    "olist_customers_dataset.csv": "customers",
    "olist_sellers_dataset.csv": "sellers",
    "olist_products_dataset.csv": "products",
    "product_category_name_translation.csv": "category_translation",
    "olist_orders_dataset.csv": "orders",
    "olist_order_items_dataset.csv": "order_items",
    "olist_order_payments_dataset.csv": "order_payments",
    "olist_order_reviews_dataset.csv": "order_reviews",
}


def load_staging() -> None:
    """Create the staging tables, then truncate + COPY each CSV into its table.

    Everything runs in ONE transaction: if any file fails, nothing is changed.
    """
    missing = [f for f in CSV_TO_STAGING_TABLE if not (RAW_DIR / f).exists()]
    if missing:
        raise FileNotFoundError(f"Missing CSV files in {RAW_DIR}: {missing}")

    hook = PostgresHook(postgres_conn_id=WAREHOUSE_CONN_ID)
    conn = hook.get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute((SQL_DIR / "staging" / "01_staging_ddl.sql").read_text())

            for filename, table in CSV_TO_STAGING_TABLE.items():
                cur.execute(f"TRUNCATE TABLE staging.{table}")
                with open(RAW_DIR / filename, "rb") as f:
                    cur.copy_expert(
                        f"COPY staging.{table} FROM STDIN "
                        "WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')",
                        f,
                    )
                log.info("Loaded %s rows into staging.%s from %s", cur.rowcount, table, filename)
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


default_args = {
    "owner": "data-team",
    "retries": 1,
    "retry_delay": timedelta(minutes=1),
}

with DAG(
    dag_id="olist_dwh",
    description="Olist CSVs -> staging -> core star schema -> reporting views",
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule=None,        # the dataset is static, so trigger runs manually
    catchup=False,
    template_searchpath=[str(SQL_DIR)],
    params={
        "full_refresh": Param(
            False,
            type="boolean",
            description="Ignore the watermark and re-process ALL orders (default: only new/changed).",
        )
    },
    tags=["olist", "dwh"],
) as dag:

    t_load_staging = PythonOperator(
        task_id="load_staging",
        python_callable=load_staging,
    )

    t_build_dims = SQLExecuteQueryOperator(
        task_id="build_dims",
        conn_id=WAREHOUSE_CONN_ID,
        sql=[
            "etl/00_etl_ddl.sql",     # watermark
            "core/00_core_ddl.sql",
            "core/10_dim_date.sql",
            "core/20_dim_customer.sql",
            "core/30_dim_product.sql",
            "core/40_dim_seller.sql",
        ],
    )

    # All files run in one transaction: if any step fails, nothing is committed
    t_build_fact = SQLExecuteQueryOperator(
        task_id="build_fact",
        conn_id=WAREHOUSE_CONN_ID,
        sql=[
            "core/45_select_batch.sql",       # which orders are new / changed?
            "core/50_fact_order_items.sql",   
            "core/60_fact_orders.sql",       
            "core/65_move_watermark.sql",     # log the run + move the watermark
        ],
    )

    t_build_reporting = SQLExecuteQueryOperator(
        task_id="build_reporting",
        conn_id=WAREHOUSE_CONN_ID,
        sql="reporting/70_reporting_views.sql",
    )

    t_load_staging >> t_build_dims >> t_build_fact >> t_build_reporting