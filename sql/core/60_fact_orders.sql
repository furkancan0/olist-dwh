TRUNCATE core.fact_orders;

INSERT INTO core.fact_orders (
    order_id, customer_key, purchase_date_key, delivered_date_key,
    estimated_delivery_date_key, order_status, payment_type, payment_installments,
    review_score, items_count, items_value, freight_value, payment_value,
    delivery_days, delivery_delay_days, is_delivered_late
)
WITH items AS (
    SELECT order_id,
           COUNT(*)           AS items_count,
           SUM(price)         AS items_value,
           SUM(freight_value) AS freight_value
    FROM core.fact_order_items
    GROUP BY order_id
),
payments AS (
    SELECT order_id,
           SUM(payment_value::numeric)              AS payment_value,
           MAX(payment_installments::int)           AS payment_installments,
           (ARRAY_AGG(payment_type ORDER BY payment_sequential::int))[1] AS payment_type
    FROM staging.order_payments
    GROUP BY order_id
),
reviews AS (
    SELECT DISTINCT ON (order_id)
           order_id,
           review_score::int AS review_score
    FROM staging.order_reviews
    ORDER BY order_id, review_answer_timestamp::timestamp DESC NULLS LAST
),
orders AS (
    SELECT order_id,
           customer_id,
           order_status,
           order_purchase_timestamp::timestamp                         AS purchased_at,
           NULLIF(order_delivered_customer_date, '')::timestamp        AS delivered_at,
           NULLIF(order_estimated_delivery_date, '')::timestamp        AS estimated_at
    FROM staging.orders
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
    o.delivered_at::date > o.estimated_at::date
FROM orders o
JOIN staging.customers c  ON c.customer_id         = o.customer_id
JOIN core.dim_customer dc ON dc.customer_unique_id = c.customer_unique_id
LEFT JOIN items    i ON i.order_id = o.order_id
LEFT JOIN payments p ON p.order_id = o.order_id
LEFT JOIN reviews  r ON r.order_id = o.order_id;

DO $$
DECLARE
    staged INT := (SELECT COUNT(*) FROM staging.orders);
    loaded INT := (SELECT COUNT(*) FROM core.fact_orders);
BEGIN
    IF staged <> loaded THEN
        RAISE EXCEPTION 'fact_orders: % rows in staging but % loaded', staged, loaded;
    END IF;
END $$;
