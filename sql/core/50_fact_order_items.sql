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
FROM etl.orders_batch b
JOIN staging.order_items  oi ON oi.order_id           = b.order_id
JOIN staging.orders       o  ON o.order_id            = oi.order_id
JOIN staging.customers    c  ON c.customer_id         = o.customer_id
JOIN core.dim_customer    dc ON dc.customer_unique_id = c.customer_unique_id
JOIN core.dim_product     dp ON dp.product_id         = oi.product_id
JOIN core.dim_seller      ds ON ds.seller_id          = oi.seller_id
ON CONFLICT (order_id, order_item_id) DO UPDATE
SET customer_key      = EXCLUDED.customer_key,
    product_key       = EXCLUDED.product_key,
    seller_key        = EXCLUDED.seller_key,
    purchase_date_key = EXCLUDED.purchase_date_key,
    price             = EXCLUDED.price,
    freight_value     = EXCLUDED.freight_value;

-- Remove items of batch orders that no longer exist in the source.
DELETE FROM core.fact_order_items f
USING etl.orders_batch b
WHERE f.order_id = b.order_id
  AND NOT EXISTS (
      SELECT 1
      FROM staging.order_items oi
      WHERE oi.order_id = f.order_id
        AND oi.order_item_id::int = f.order_item_id
  );


DO $$
DECLARE
    staged INT := (SELECT COUNT(*) FROM staging.order_items oi
                   JOIN etl.orders_batch b ON b.order_id = oi.order_id);
    loaded INT := (SELECT COUNT(*) FROM core.fact_order_items f
                   JOIN etl.orders_batch b ON b.order_id = f.order_id);
BEGIN
    IF staged <> loaded THEN
        RAISE EXCEPTION 'fact_order_items: % items in staging but % loaded for the batch', staged, loaded;
    END IF;
END $$;