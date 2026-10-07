TRUNCATE core.dim_customer RESTART IDENTITY CASCADE;

INSERT INTO core.dim_customer (customer_unique_id, zip_code_prefix, city, state)
SELECT DISTINCT ON (c.customer_unique_id)
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    INITCAP(TRIM(c.customer_city)),
    UPPER(TRIM(c.customer_state))
FROM staging.customers c
LEFT JOIN staging.orders o ON o.customer_id = c.customer_id
ORDER BY c.customer_unique_id,
         o.order_purchase_timestamp::timestamp DESC NULLS LAST;
