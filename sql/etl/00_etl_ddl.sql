CREATE SCHEMA IF NOT EXISTS etl;

--The watermark: "I have processed every order changed up to this timestamp".
CREATE TABLE IF NOT EXISTS etl.watermark (
    pipeline_name   TEXT PRIMARY KEY,
    last_watermark  TIMESTAMP   NOT NULL,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO etl.watermark (pipeline_name, last_watermark)
VALUES ('fact_orders', '-infinity')
ON CONFLICT (pipeline_name) DO NOTHING;

CREATE TABLE IF NOT EXISTS etl.load_log (
    log_id            BIGSERIAL PRIMARY KEY,
    pipeline_name     TEXT        NOT NULL,
    run_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    full_refresh      BOOLEAN     NOT NULL,
    watermark_before  TIMESTAMP,
    watermark_after   TIMESTAMP,
    rows_new          INT         NOT NULL,   -- orders never seen before
    rows_changed      INT         NOT NULL    -- known orders that changed
);

--Batch: orders the current run will reprocess.
CREATE TABLE IF NOT EXISTS etl.orders_batch (
    order_id          TEXT PRIMARY KEY,
    order_updated_at  TIMESTAMP NOT NULL,
    change_type       TEXT NOT NULL CHECK (change_type IN ('new', 'changed'))
);