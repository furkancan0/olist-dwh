-- STEP 1 of the incremental fact load: decide WHICH orders to process.
--
-- Every order gets an "order_updated_at" = the latest timestamp we know about it:
--   purchase, approved, handed to carrier, delivered, or last review answered.
-- Olist has no "updated_at" column, but an order moves forward through these
-- steps (approved -> shipped -> delivered -> reviewed), so every normal status
-- change pushes this timestamp forward. That makes it a good WATERMARK column.
--
-- An order goes into the batch when ANY of these is true:
--   1. it is not in fact_orders yet                  -> 'new'
--   2. order_updated_at is newer than the watermark   -> 'changed'   (the watermark rule)
--   3. its status differs from the one in fact_orders -> 'changed'   (safety net, e.g. a
--      cancellation that did not add a new timestamp)
--
-- Full refresh (DAG parameter full_refresh = true) ignores the watermark and takes everything.
-- Note: the TRUE/FALSE switch in the 'wm' CTE below is Airflow (Jinja) templating:
-- Airflow replaces it with the real value of full_refresh before the SQL is sent to Postgres.

TRUNCATE etl.orders_batch;

INSERT INTO etl.orders_batch (order_id, order_updated_at, change_type)
WITH last_review AS (
    SELECT order_id,
           MAX(NULLIF(review_answer_timestamp, '')::timestamp) AS reviewed_at
    FROM staging.order_reviews
    GROUP BY order_id
),
src AS (
    SELECT o.order_id,
           o.order_status,
           GREATEST(
               o.order_purchase_timestamp::timestamp,
               NULLIF(o.order_approved_at, '')::timestamp,
               NULLIF(o.order_delivered_carrier_date, '')::timestamp,
               NULLIF(o.order_delivered_customer_date, '')::timestamp,
               r.reviewed_at
           ) AS order_updated_at 
    FROM staging.orders o
    LEFT JOIN last_review r ON r.order_id = o.order_id
),
wm AS (
    SELECT CASE WHEN {{ 'TRUE' if params.full_refresh else 'FALSE' }}
                THEN '-infinity'::timestamp
                ELSE last_watermark END AS value
    FROM etl.watermark
    WHERE pipeline_name = 'fact_orders'
)
SELECT s.order_id,
       s.order_updated_at,
       CASE WHEN f.order_id IS NULL THEN 'new' ELSE 'changed' END
FROM src s
CROSS JOIN wm
LEFT JOIN core.fact_orders f ON f.order_id = s.order_id
WHERE f.order_id IS NULL                              -- rule 1: unknown order
   OR s.order_updated_at > wm.value                   -- rule 2: newer than the watermark
   OR f.order_status <> s.order_status;               -- rule 3: status changed
