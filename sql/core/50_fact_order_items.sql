TRUNCATE core.fact_order_items;

INSERT INTO core.fact_order_items (
    order_id, order_item_id, customer_key, product_key, seller_key,
    purchase_date_key, price, freight_value
)
SELECT
    oi.order_id,
    oi.order_item_id::int,
    dc.customer_key,
    dp.product_key,
    ds.seller_key,
    TO_CHAR(o.order_purchase_timestamp::timestamp, 'YYYYMMDD')::int,
    oi.price::numeric(10,2),
    oi.freight_value::numeric(10,2)
FROM staging.order_items oi
JOIN staging.orders       o  ON o.order_id            = oi.order_id
JOIN staging.customers    c  ON c.customer_id         = o.customer_id
JOIN core.dim_customer    dc ON dc.customer_unique_id = c.customer_unique_id
JOIN core.dim_product     dp ON dp.product_id         = oi.product_id
JOIN core.dim_seller      ds ON ds.seller_id          = oi.seller_id;

DO $$
DECLARE
    staged INT := (SELECT COUNT(*) FROM staging.order_items);
    loaded INT := (SELECT COUNT(*) FROM core.fact_order_items);
BEGIN
    IF staged <> loaded THEN
        RAISE EXCEPTION 'fact_order_items: % rows in staging but % loaded', staged, loaded;
    END IF;
END $$;
