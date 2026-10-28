CREATE OR REPLACE VIEW ml.vw_late_delivery_features AS
WITH item_stats AS (
    SELECT i.order_id,
           COUNT(DISTINCT i.seller_key)                       AS n_sellers,
           COUNT(DISTINCT i.product_key)                      AS n_products,
           SUM(p.weight_g)::float8                            AS total_weight_g,
           SUM(p.length_cm * p.height_cm * p.width_cm)::float8 AS total_volume_cm3
    FROM core.fact_order_items i
    JOIN core.dim_product p ON p.product_key = i.product_key
    GROUP BY i.order_id
),
main_item AS (
    SELECT DISTINCT ON (i.order_id)
           i.order_id,
           p.category_name_en AS main_category,
           s.state            AS seller_state
    FROM core.fact_order_items i
    JOIN core.dim_product p ON p.product_key = i.product_key
    JOIN core.dim_seller  s ON s.seller_key  = i.seller_key
    ORDER BY i.order_id, i.price DESC, i.order_item_id
)
SELECT
    f.order_id,
    d.full_date                                   AS purchase_date,

    CASE WHEN f.delivered_date_key IS NULL THEN NULL
         ELSE f.is_delivered_late::int END        AS is_late,

    d.month                                       AS purchase_month,
    d.day_of_week                                 AS purchase_weekday,
    (e.full_date - d.full_date)                   AS estimated_days,         -- days Olist PROMISED at checkout

    f.items_count                                 AS n_items,
    st.n_sellers,
    st.n_products,
    f.items_value::float8                         AS items_value,
    f.freight_value::float8                       AS freight_value,
    CASE WHEN f.items_value > 0
         THEN (f.freight_value / f.items_value)::float8 END AS freight_ratio,
    st.total_weight_g,
    st.total_volume_cm3,
    mi.main_category,

    f.payment_type,
    f.payment_installments,

    c.state                                       AS customer_state,
    mi.seller_state,
    (c.state = mi.seller_state)::int              AS same_state
FROM core.fact_orders f
JOIN core.dim_date     d  ON d.date_key      = f.purchase_date_key
JOIN core.dim_date     e  ON e.date_key      = f.estimated_delivery_date_key
JOIN core.dim_customer c  ON c.customer_key  = f.customer_key
JOIN item_stats        st ON st.order_id     = f.order_id
JOIN main_item         mi ON mi.order_id     = f.order_id
WHERE (f.order_status = 'delivered' AND f.delivered_date_key IS NOT NULL)
 OR (f.delivered_date_key IS NULL AND f.order_status NOT IN ('delivered', 'canceled', 'unavailable'));

CREATE OR REPLACE VIEW ml.vw_open_orders_at_risk AS
SELECT
    p.order_id,
    p.purchase_date,
    o.order_status,
    c.state AS customer_state,
    p.late_probability,
    p.risk_level
FROM ml.order_late_predictions p
JOIN core.fact_orders  o ON o.order_id     = p.order_id
JOIN core.dim_customer c ON c.customer_key = o.customer_key
WHERE p.data_split = 'open'
ORDER BY p.late_probability DESC;

CREATE OR REPLACE VIEW ml.vw_test_risk_deciles AS
SELECT
    risk_group,
    COUNT(*)                                          AS orders,
    ROUND(AVG(late_probability), 4)                   AS avg_predicted,
    ROUND(AVG(actual_is_late::int), 4)                AS actual_late_rate,
    SUM(actual_is_late::int)                          AS late_orders
FROM (
    SELECT late_probability, actual_is_late,
           NTILE(10) OVER (ORDER BY late_probability) AS risk_group
    FROM ml.order_late_predictions
    WHERE data_split = 'test'
) t
GROUP BY risk_group
ORDER BY risk_group;