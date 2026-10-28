from __future__ import annotations

import io
import logging
import os
from datetime import datetime
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score, roc_auc_score

log = logging.getLogger(__name__)

MODEL_NAME = "late_delivery_lgbm"
LABEL = "is_late" # 1 = late, 0 = on time

NUMERIC_FEATURES = [
    "purchase_month", "purchase_weekday", "estimated_days",
    "n_items", "n_sellers", "n_products",
    "items_value", "freight_value", "freight_ratio",
    "total_weight_g", "total_volume_cm3",
    "payment_installments", "same_state",
]
CATEGORICAL_FEATURES = ["payment_type", "customer_state", "seller_state", "main_category"]
FEATURES = NUMERIC_FEATURES + CATEGORICAL_FEATURES

TRAIN_FRACTION = 0.70  
VALID_FRACTION = 0.15      

ALERT_RATE = 0.10           
RANDOM_SEED = 42            

def load_data(conn) -> pd.DataFrame:
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM ml.vw_late_delivery_features")
        columns = [c.name for c in cur.description]
        df = pd.DataFrame(cur.fetchall(), columns=columns)
    df["purchase_date"] = pd.to_datetime(df["purchase_date"])
    return df


def prepare_features(df: pd.DataFrame) -> pd.DataFrame:
    # LightGBM handles missing values by itself, no need to invent a value.
    for col in NUMERIC_FEATURES + [LABEL]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    for col in CATEGORICAL_FEATURES:
        df[col] = df[col].fillna("unknown").astype("category")
    return df


def split_by_time(df: pd.DataFrame):
    labelled = (df[df[LABEL].notna()]
                .sort_values(["purchase_date", "order_id"])
                .reset_index(drop=True))
    if len(labelled) < 1000:
        raise ValueError(
            f"Only {len(labelled)} delivered orders with a known answer: too few to train. "
            "Did build_fact run? (check core.fact_orders)"
        )

    n = len(labelled)
    valid_from = labelled.loc[int(n * TRAIN_FRACTION), "purchase_date"]
    test_from = labelled.loc[int(n * (TRAIN_FRACTION + VALID_FRACTION)), "purchase_date"]

    train = labelled[labelled["purchase_date"] < valid_from]
    valid = labelled[(labelled["purchase_date"] >= valid_from) & (labelled["purchase_date"] < test_from)]
    test = labelled[labelled["purchase_date"] >= test_from]
    open_orders = df[df[LABEL].isna()]          # not delivered yet

    if test[LABEL].sum() == 0 or valid[LABEL].sum() == 0:
        raise ValueError("The validation or test set has no late order at all; cannot measure the model.")
    return train, valid, test, open_orders, valid_from, test_from


def train_model(train: pd.DataFrame, valid: pd.DataFrame) -> lgb.LGBMClassifier:

    model = lgb.LGBMClassifier(
        objective="binary",        # late / not late
        n_estimators=1000,         # maximum number of trees
        learning_rate=0.05,        # small steps = slower but more careful learning
        num_leaves=31,             # how complex each tree may be
        min_child_samples=50,      # a rule must be backed by at least 50 orders
        subsample=0.8,          
        subsample_freq=1,
        colsample_bytree=0.8,      # random 80% of the columns (overfitting)
        reg_lambda=1.0,
        random_state=RANDOM_SEED,
        deterministic=True,    
        force_row_wise=True,
        verbose=-1,
    )
    model.fit(
        train[FEATURES], train[LABEL].astype(int),
        eval_X=valid[FEATURES], eval_y=valid[LABEL].astype(int), 
        eval_metric="auc",
        callbacks=[lgb.early_stopping(stopping_rounds=50, verbose=False)],
    )
    return model


def evaluate(y_test: np.ndarray, p_test: np.ndarray, alert_threshold: float) -> dict:

    flagged = p_test >= alert_threshold
    late_rate = float(y_test.mean())
    precision = float(y_test[flagged].mean()) if flagged.any() else 0.0
    return {
        "late_rate": late_rate,
        "roc_auc": float(roc_auc_score(y_test, p_test)),
        "pr_auc": float(average_precision_score(y_test, p_test)),
        "baseline_pr_auc": late_rate,
        "flagged_pct": float(flagged.mean()),
        "flagged_precision": precision,
        "flagged_recall": float(y_test[flagged].sum() / y_test.sum()),
        "lift": precision / late_rate if late_rate > 0 else 0.0,
    }


def _log_report(m, sizes, dates, importance, n_open, best_iteration, threshold):
    top = ", ".join(f"{name} ({pct:.0f}%)" for name, pct in importance[:5])
    log.info(
        "\n"
        "==================== LATE-DELIVERY MODEL REPORT ====================\n"
        "DATA     %s delivered orders with a known answer, plus %s open orders to predict\n"
        "SPLIT    train %s orders (before %s) | validation %s (before %s) | test %s (from %s)\n"
        "TRAINING stopped after %s trees (early stopping)\n"
        "\n"
        "HOW GOOD IS IT?  (measured on the %s TEST orders the model never saw)\n"
        "  Late rate in the test period .... %.1f%%\n"
        "  ROC-AUC ......................... %.3f   (0.5 = coin flip, 1.0 = perfect)\n"
        "  PR-AUC .......................... %.3f   (no-skill model would get about %.3f)\n"
        "\n"
        "ALERT RULE: flag orders with risk >= %.3f  (picked so ~10%% of validation orders get flagged)\n"
        "  On the test orders it flags ............ %.1f%%  (differs from 10%% because the mix of orders changes over time)\n"
        "  Flagged orders that really were late ... %.1f%%   (%.1fx better than picking at random)\n"
        "  Late orders we managed to catch ........ %.1f%%\n"
        "\n"
        "WHAT THE MODEL RELIED ON MOST:  %s\n"
        "=====================================================================",
        f"{sizes['labelled']:,}", f"{n_open:,}",
        f"{sizes['train']:,}", dates["valid_from"], f"{sizes['valid']:,}", dates["test_from"],
        f"{sizes['test']:,}", dates["test_from"],
        best_iteration,
        f"{sizes['test']:,}",
        m["late_rate"] * 100, m["roc_auc"], m["pr_auc"], m["baseline_pr_auc"],
        threshold, m["flagged_pct"] * 100,
        m["flagged_precision"] * 100, m["lift"], m["flagged_recall"] * 100,
        top,
    )


def save_results(conn, model, metrics, sizes, dates, importance, predictions, threshold, model_path):
    """All writes happen in ONE transaction: either everything is saved or nothing is."""
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO ml.model_runs (
                model_name, train_rows, valid_rows, test_rows, valid_from_date, test_from_date,
                late_rate_test, roc_auc, pr_auc, baseline_pr_auc, alert_threshold,
                flagged_pct, flagged_precision, flagged_recall, lift, best_iteration, model_path)
            VALUES (%s,%s,%s,%s,%s,%s, %s,%s,%s,%s,%s, %s,%s,%s,%s,%s,%s)
            RETURNING run_id
            """,
            (MODEL_NAME, sizes["train"], sizes["valid"], sizes["test"],
             dates["valid_from"], dates["test_from"],
             round(metrics["late_rate"], 4), round(metrics["roc_auc"], 4), round(metrics["pr_auc"], 4),
             round(metrics["baseline_pr_auc"], 4), round(threshold, 4),
             round(metrics["flagged_pct"], 4), round(metrics["flagged_precision"], 4),
             round(metrics["flagged_recall"], 4), round(metrics["lift"], 2),
             int(model.best_iteration_), str(model_path)),
        )
        run_id = cur.fetchone()[0]

        cur.executemany(
            "INSERT INTO ml.feature_importance (run_id, feature, importance_pct) VALUES (%s, %s, %s)",
            [(run_id, name, round(pct, 2)) for name, pct in importance],
        )

        cur.execute("SELECT COUNT(*) FROM ml.order_late_predictions")
        old_rows = cur.fetchone()[0]
        cur.execute("TRUNCATE ml.order_late_predictions")

        out = predictions.copy()
        out.insert(1, "run_id", run_id)
        buf = io.StringIO()
        out.to_csv(buf, index=False, header=False) 
        buf.seek(0)
        cur.copy_expert(
            "COPY ml.order_late_predictions "
            "(order_id, run_id, data_split, purchase_date, late_probability, risk_level, actual_is_late) "
            "FROM STDIN WITH (FORMAT csv)",
            buf,
        )
    conn.commit()
    return run_id, old_rows


def run_late_delivery_model(conn, model_dir: Path) -> dict:
    """Train, evaluate, save, score. Returns the rows written, in the shape the audit log expects."""
    model_dir = Path(model_dir)

    df = prepare_features(load_data(conn))                                      
    train, valid, test, open_orders, valid_from, test_from = split_by_time(df)   
    model = train_model(train, valid)                                           

    p_valid = model.predict_proba(valid[FEATURES])[:, 1]
    p_test = model.predict_proba(test[FEATURES])[:, 1]

    threshold = float(np.quantile(p_valid, 1 - ALERT_RATE))

    y_test = test[LABEL].astype(int).to_numpy()
    metrics = evaluate(y_test, p_test, threshold)                               

    # Which columns did the model use most?
    gain = model.booster_.feature_importance(importance_type="gain")
    share = 100 * gain / gain.sum()
    importance = sorted(zip(FEATURES, share.tolist()), key=lambda x: x[1], reverse=True)

    sizes = {"labelled": len(train) + len(valid) + len(test),
             "train": len(train), "valid": len(valid), "test": len(test)}
    dates = {"valid_from": valid_from.date(), "test_from": test_from.date()}
    _log_report(metrics, sizes, dates, importance, len(open_orders), model.best_iteration_, threshold)

    p_open = model.predict_proba(open_orders[FEATURES])[:, 1] if len(open_orders) else np.array([])
    predictions = pd.concat([
        pd.DataFrame({"order_id": test["order_id"].to_numpy(), "data_split": "test",
                      "purchase_date": test["purchase_date"].dt.date.to_numpy(),
                      "late_probability": p_test.round(4), "actual_is_late": y_test}),
        pd.DataFrame({"order_id": open_orders["order_id"].to_numpy(), "data_split": "open",
                      "purchase_date": open_orders["purchase_date"].dt.date.to_numpy(),
                      "late_probability": p_open.round(4), "actual_is_late": np.nan}),
    ], ignore_index=True)
    predictions["risk_level"] = np.where(predictions["late_probability"] >= threshold, "high", "normal")
    predictions = predictions[["order_id", "data_split", "purchase_date", "late_probability",
                               "risk_level", "actual_is_late"]]
    predictions["actual_is_late"] = predictions["actual_is_late"].astype("Int64")   # 1 / 0 / empty

    model_dir.mkdir(parents=True, exist_ok=True)
    model_path = model_dir / f"{MODEL_NAME}_{datetime.now():%Y%m%d_%H%M%S}.txt"
    model.booster_.save_model(str(model_path))

    try:
        run_id, old_rows = save_results(conn, model, metrics, sizes, dates, importance,
                                        predictions, threshold, model_path)
    except Exception:
        conn.rollback()
        model_path.unlink(missing_ok=True)     
        raise
    log.info("Saved run_id=%s: %s predictions in ml.order_late_predictions, model file %s",
             run_id, f"{len(predictions):,}", model_path.name)

    return {
        "ml.model_runs": {"inserted": 1, "updated": 0, "deleted": 0},
        "ml.feature_importance": {"inserted": len(importance), "updated": 0, "deleted": 0},
        "ml.order_late_predictions": {"inserted": len(predictions), "updated": 0, "deleted": old_rows},
    }


if __name__ == "__main__":
    import psycopg2

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    dsn = os.getenv("WAREHOUSE_DSN", "postgresql://dw_user:dw_pass@localhost:5432/olist_dw")
    connection = psycopg2.connect(dsn)
    try:
        run_late_delivery_model(connection, Path(__file__).resolve().parents[1] / "models")
    finally:
        connection.close()