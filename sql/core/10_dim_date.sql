TRUNCATE core.dim_date CASCADE;

INSERT INTO core.dim_date (
    date_key, full_date, year, quarter, month, month_name, year_month,
    day_of_month, day_of_week, day_name, is_weekend
)
WITH bounds AS (
    SELECT
        MIN(order_purchase_timestamp::timestamp)::date AS first_day,
        GREATEST(
            MAX(order_estimated_delivery_date::timestamp),
            MAX(NULLIF(order_delivered_customer_date, '')::timestamp)
        )::date AS last_day
    FROM staging.orders
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::int,
    d::date,
    EXTRACT(YEAR    FROM d)::int,
    EXTRACT(QUARTER FROM d)::int,
    EXTRACT(MONTH   FROM d)::int,
    TRIM(TO_CHAR(d, 'Month')),
    TO_CHAR(d, 'YYYY-MM'),
    EXTRACT(DAY     FROM d)::int,
    EXTRACT(ISODOW  FROM d)::int,
    TRIM(TO_CHAR(d, 'Day')),
    EXTRACT(ISODOW  FROM d) IN (6, 7)
FROM bounds,
     GENERATE_SERIES(bounds.first_day::timestamp, bounds.last_day::timestamp, INTERVAL '1 day') AS d;
