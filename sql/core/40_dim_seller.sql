TRUNCATE core.dim_seller RESTART IDENTITY CASCADE;

INSERT INTO core.dim_seller (seller_id, zip_code_prefix, city, state)
SELECT
    seller_id,
    seller_zip_code_prefix,
    INITCAP(TRIM(seller_city)),
    UPPER(TRIM(seller_state))
FROM staging.sellers;
