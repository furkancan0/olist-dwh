--   ml.model_runs how good was the model?
--   ml.feature_importance  which input columns the model relied on
--   ml.order_late_predictions  the predictions of the LATEST run

CREATE SCHEMA IF NOT EXISTS ml;

CREATE TABLE IF NOT EXISTS ml.model_runs (
    run_id             BIGSERIAL PRIMARY KEY,
    model_name         TEXT        NOT NULL,
    trained_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- The time-based split
    train_rows         INT NOT NULL,
    valid_rows         INT NOT NULL,
    test_rows          INT NOT NULL,
    valid_from_date    DATE,                 -- validation set starts on this purchase date
    test_from_date     DATE,                 -- test set starts on this purchase date
    late_rate_test     NUMERIC(6,4),         
    roc_auc            NUMERIC(6,4),         -- 0.5 = coin flip, 1.0 = perfect
    pr_auc             NUMERIC(6,4),         
    baseline_pr_auc    NUMERIC(6,4),
    alert_threshold    NUMERIC(6,4),         
    flagged_pct        NUMERIC(6,4),         
    flagged_precision  NUMERIC(6,4),         
    flagged_recall     NUMERIC(6,4),         
    lift               NUMERIC(8,2),         

    best_iteration     INT,                  
    model_path         TEXT
);

CREATE TABLE IF NOT EXISTS ml.feature_importance (
    run_id          BIGINT NOT NULL REFERENCES ml.model_runs (run_id) ON DELETE CASCADE,
    feature         TEXT   NOT NULL,
    importance_pct  NUMERIC(6,2) NOT NULL,
    PRIMARY KEY (run_id, feature)
);


CREATE TABLE IF NOT EXISTS ml.order_late_predictions (
    order_id          TEXT PRIMARY KEY,
    run_id            BIGINT NOT NULL REFERENCES ml.model_runs (run_id),
    data_split        TEXT   NOT NULL CHECK (data_split IN ('test', 'open')),
    purchase_date     DATE   NOT NULL,
    late_probability  NUMERIC(6,4) NOT NULL,
    risk_level        TEXT   NOT NULL CHECK (risk_level IN ('high', 'normal')),
    actual_is_late    BOOLEAN,                 -- NULL for open orders (not delivered yet)
    scored_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);