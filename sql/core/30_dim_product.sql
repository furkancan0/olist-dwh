TRUNCATE core.dim_product RESTART IDENTITY CASCADE;

INSERT INTO core.dim_product (
    product_id, category_name_pt, category_name_en,
    name_length, description_length, photos_qty,
    weight_g, length_cm, height_cm, width_cm
)
SELECT
    p.product_id,
    COALESCE(NULLIF(p.product_category_name, ''), 'unknown'),
    COALESCE(t.product_category_name_english,
             NULLIF(p.product_category_name, ''),
             'unknown'),
    NULLIF(p.product_name_lenght, '')::numeric::int,
    NULLIF(p.product_description_lenght, '')::numeric::int,
    NULLIF(p.product_photos_qty, '')::numeric::int,
    NULLIF(p.product_weight_g, '')::numeric::int,
    NULLIF(p.product_length_cm, '')::numeric::int,
    NULLIF(p.product_height_cm, '')::numeric::int,
    NULLIF(p.product_width_cm, '')::numeric::int
FROM staging.products p
LEFT JOIN staging.category_translation t
       ON t.product_category_name = p.product_category_name;
