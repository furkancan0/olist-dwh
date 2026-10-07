CREATE SCHEMA IF NOT EXISTS reporting;

-- Sales per month 
CREATE OR REPLACE VIEW reporting.vw_monthly_sales AS
SELECT
    d.year_month,
    d.year,
    d.month,
    COUNT(*)                                       AS orders,
    COUNT(DISTINCT f.customer_key)                 AS customers,
    SUM(f.items_value)                             AS revenue,
    SUM(f.freight_value)                           AS freight,
    ROUND(SUM(f.items_value) / COUNT(*), 2)        AS avg_order_value
FROM core.fact_orders f
JOIN core.dim_date d ON d.date_key = f.purchase_date_key
WHERE f.order_status NOT IN ('canceled', 'unavailable')
GROUP BY d.year_month, d.year, d.month
ORDER BY d.year_month;

-- Sales per product category
CREATE OR REPLACE VIEW reporting.vw_sales_by_category AS
SELECT
    p.category_name_en                             AS category,
    COUNT(*)                                       AS items_sold,
    COUNT(DISTINCT i.order_id)                     AS orders,
    SUM(i.price)                                   AS revenue,
    ROUND(AVG(i.price), 2)                         AS avg_item_price
FROM core.fact_order_items i
JOIN core.fact_orders  o ON o.order_id    = i.order_id
JOIN core.dim_product  p ON p.product_key = i.product_key
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY p.category_name_en
ORDER BY revenue DESC;

-- Delivery performance per customer state
CREATE OR REPLACE VIEW reporting.vw_delivery_by_state AS
SELECT
    c.state,
    COUNT(*)                                                   AS delivered_orders,
    ROUND(AVG(f.delivery_days), 1)                             AS avg_delivery_days,
    ROUND(100.0 * AVG(CASE WHEN f.is_delivered_late THEN 1 ELSE 0 END), 1) AS late_pct,
    ROUND(AVG(f.review_score), 2)                              AS avg_review_score
FROM core.fact_orders f
JOIN core.dim_customer c ON c.customer_key = f.customer_key
WHERE f.order_status = 'delivered'
  AND f.delivered_date_key IS NOT NULL
GROUP BY c.state
ORDER BY delivered_orders DESC;

-- Seller score card
CREATE OR REPLACE VIEW reporting.vw_seller_scorecard AS
SELECT
    s.seller_id,
    s.city,
    s.state,
    COUNT(*)                          AS items_sold,
    COUNT(DISTINCT i.order_id)        AS orders,
    SUM(i.price)                      AS revenue,
    ROUND(AVG(o.review_score), 2)     AS avg_review_score
FROM core.fact_order_items i
JOIN core.fact_orders o ON o.order_id   = i.order_id
JOIN core.dim_seller  s ON s.seller_key = i.seller_key
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY s.seller_id, s.city, s.state
ORDER BY revenue DESC;

-- Payment methods
CREATE OR REPLACE VIEW reporting.vw_payment_methods AS
SELECT
    COALESCE(payment_type, 'unknown')          AS payment_type,
    COUNT(*)                                   AS orders,
    SUM(payment_value)                         AS total_paid,
    ROUND(AVG(payment_installments), 1)        AS avg_installments
FROM core.fact_orders
WHERE order_status NOT IN ('canceled', 'unavailable')
GROUP BY COALESCE(payment_type, 'unknown')
ORDER BY orders DESC;
