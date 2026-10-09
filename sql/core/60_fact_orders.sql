INSERT INTO core.fact_orders (
    order_id, customer_key, purchase_date_key, delivered_date_key,
    estimated_delivery_date_key, order_status, payment_type, payment_installments,
    review_score, items_count, items_value, freight_value, payment_value,
    delivery_days, delivery_delay_days, is_delivered_late, order_updated_at
)
WITH items AS (
    SELECT i.order_id,
           COUNT(*)             AS items_count,
           SUM(i.price)         AS items_value,
           SUM(i.freight_value) AS freight_value
    FROM core.fact_order_items i
    JOIN etl.orders_batch b ON b.order_id = i.order_id
    GROUP BY i.order_id
),
payments AS (
    SELECT p.order_id,
           SUM(p.payment_value::numeric)              AS payment_value,
           MAX(p.payment_installments::int)           AS payment_installments,
           (ARRAY_AGG(p.payment_type ORDER BY p.payment_sequential::int))[1] AS payment_type
    FROM staging.order_payments p
    JOIN etl.orders_batch b ON b.order_id = p.order_id
    GROUP BY p.order_id
),
reviews AS (
    -- keep only the most recent review.
    SELECT DISTINCT ON (r.order_id)
           r.order_id,
           r.review_score::int AS review_score
    FROM staging.order_reviews r
    JOIN etl.orders_batch b ON b.order_id = r.order_id
    ORDER BY r.order_id, r.review_answer_timestamp::timestamp DESC NULLS LAST
),
orders AS (
    SELECT o.order_id,
           o.customer_id,
           o.order_status,
           o.order_purchase_timestamp::timestamp                  AS purchased_at,
           NULLIF(o.order_delivered_customer_date, '')::timestamp AS delivered_at,
           NULLIF(o.order_estimated_delivery_date, '')::timestamp AS estimated_at,
           b.order_updated_at
    FROM staging.orders o
    JOIN etl.orders_batch b ON b.order_id = o.order_id
)
SELECT
    o.order_id,
    dc.customer_key,
    TO_CHAR(o.purchased_at, 'YYYYMMDD')::int,
    TO_CHAR(o.delivered_at, 'YYYYMMDD')::int,       
    TO_CHAR(o.estimated_at, 'YYYYMMDD')::int,
    o.order_status,
    p.payment_type,
    p.payment_installments,
    r.review_score,
    COALESCE(i.items_count, 0),                     
    COALESCE(i.items_value, 0),
    COALESCE(i.freight_value, 0),
    p.payment_value,
    o.delivered_at::date - o.purchased_at::date,    
    o.delivered_at::date - o.estimated_at::date,
    o.delivered_at::date > o.estimated_at::date,
    o.order_updated_at
FROM orders o
JOIN staging.customers c  ON c.customer_id         = o.customer_id
JOIN core.dim_customer dc ON dc.customer_unique_id = c.customer_unique_id
LEFT JOIN items    i ON i.order_id = o.order_id
LEFT JOIN payments p ON p.order_id = o.order_id
LEFT JOIN reviews  r ON r.order_id = o.order_id
ON CONFLICT (order_id) DO UPDATE
SET customer_key                = EXCLUDED.customer_key,
    purchase_date_key           = EXCLUDED.purchase_date_key,
    delivered_date_key          = EXCLUDED.delivered_date_key,
    estimated_delivery_date_key = EXCLUDED.estimated_delivery_date_key,
    order_status                = EXCLUDED.order_status,
    payment_type                = EXCLUDED.payment_type,
    payment_installments        = EXCLUDED.payment_installments,
    review_score                = EXCLUDED.review_score,
    items_count                 = EXCLUDED.items_count,
    items_value                 = EXCLUDED.items_value,
    freight_value               = EXCLUDED.freight_value,
    payment_value               = EXCLUDED.payment_value,
    delivery_days               = EXCLUDED.delivery_days,
    delivery_delay_days         = EXCLUDED.delivery_delay_days,
    is_delivered_late           = EXCLUDED.is_delivered_late,
    order_updated_at            = EXCLUDED.order_updated_at,
    etl_updated_at              = NOW();

-- Safety check
DO $$
DECLARE
    missing INT := (SELECT COUNT(*)
                    FROM etl.orders_batch b
                    LEFT JOIN core.fact_orders f ON f.order_id = b.order_id
                    WHERE f.order_id IS NULL);
BEGIN
    IF missing > 0 THEN
        RAISE EXCEPTION 'fact_orders: % orders of the batch were not loaded (missing customer?)', missing;
    END IF;
END $$;