-- This runs in the same transaction it is all-or-nothing
-- if any earlier step fails, the watermark does not move and the next run retries.

INSERT INTO etl.load_log (pipeline_name, full_refresh, watermark_before, watermark_after, rows_new, rows_changed)
SELECT
    'fact_orders',
    {{ 'TRUE' if params.full_refresh else 'FALSE' }},
    w.last_watermark,
    GREATEST(w.last_watermark, COALESCE(MAX(b.order_updated_at), w.last_watermark)),
    COUNT(*) FILTER (WHERE b.change_type = 'new'),
    COUNT(*) FILTER (WHERE b.change_type = 'changed')
FROM etl.watermark w
LEFT JOIN etl.orders_batch b ON TRUE
WHERE w.pipeline_name = 'fact_orders'
GROUP BY w.last_watermark;

-- Move the watermark 
UPDATE etl.watermark
SET last_watermark = GREATEST(last_watermark,
                              COALESCE((SELECT MAX(order_updated_at) FROM etl.orders_batch), last_watermark)),
    updated_at     = NOW()
WHERE pipeline_name = 'fact_orders';
