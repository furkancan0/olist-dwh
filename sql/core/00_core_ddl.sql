CREATE SCHEMA IF NOT EXISTS core;

CREATE TABLE IF NOT EXISTS core.dim_date (
    date_key      INT PRIMARY KEY,      
    full_date     DATE NOT NULL UNIQUE,
    year          INT  NOT NULL,
    quarter       INT  NOT NULL,
    month         INT  NOT NULL,
    month_name    TEXT NOT NULL,
    year_month    TEXT NOT NULL, 
    day_of_month  INT  NOT NULL,
    day_of_week   INT  NOT NULL,   
    day_name      TEXT NOT NULL,
    is_weekend    BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS core.dim_customer (
    customer_key        SERIAL PRIMARY KEY,   
    customer_unique_id  TEXT NOT NULL UNIQUE,
    zip_code_prefix     TEXT,
    city                TEXT,
    state               TEXT
);

CREATE TABLE IF NOT EXISTS core.dim_product (
    product_key         SERIAL PRIMARY KEY,
    product_id          TEXT NOT NULL UNIQUE,
    category_name_pt    TEXT NOT NULL,
    category_name_en    TEXT NOT NULL,
    name_length         INT,
    description_length  INT,
    photos_qty          INT,
    weight_g            INT,
    length_cm           INT,
    height_cm           INT,
    width_cm            INT
);

CREATE TABLE IF NOT EXISTS core.dim_seller (
    seller_key       SERIAL PRIMARY KEY,
    seller_id        TEXT NOT NULL UNIQUE,
    zip_code_prefix  TEXT,
    city             TEXT,
    state            TEXT
);

CREATE TABLE IF NOT EXISTS core.fact_orders (
    order_id                   TEXT PRIMARY KEY,   
    customer_key               INT  NOT NULL REFERENCES core.dim_customer (customer_key),
    purchase_date_key          INT  NOT NULL REFERENCES core.dim_date (date_key),
    delivered_date_key         INT  REFERENCES core.dim_date (date_key), 
    estimated_delivery_date_key INT REFERENCES core.dim_date (date_key),
    order_status               TEXT NOT NULL,
    payment_type               TEXT,            
    payment_installments       INT,
    review_score               INT,               
    items_count                INT  NOT NULL,
    items_value                NUMERIC(12,2) NOT NULL,   
    freight_value              NUMERIC(12,2) NOT NULL,
    payment_value              NUMERIC(12,2),
    delivery_days              INT,            
    delivery_delay_days        INT,                
    is_delivered_late          BOOLEAN,
    order_updated_at           TIMESTAMP,          -- the watermark column
    etl_inserted_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    etl_updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()  
);

ALTER TABLE core.fact_orders ADD COLUMN IF NOT EXISTS order_updated_at TIMESTAMP;
ALTER TABLE core.fact_orders ADD COLUMN IF NOT EXISTS etl_inserted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE core.fact_orders ADD COLUMN IF NOT EXISTS etl_updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE TABLE IF NOT EXISTS core.fact_order_items (
    order_id           TEXT NOT NULL,
    order_item_id      INT  NOT NULL,              
    customer_key       INT  NOT NULL REFERENCES core.dim_customer (customer_key),
    product_key        INT  NOT NULL REFERENCES core.dim_product (product_key),
    seller_key         INT  NOT NULL REFERENCES core.dim_seller (seller_key),
    purchase_date_key  INT  NOT NULL REFERENCES core.dim_date (date_key),
    price              NUMERIC(10,2) NOT NULL,
    freight_value      NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);

CREATE INDEX IF NOT EXISTS ix_fact_orders_customer   ON core.fact_orders (customer_key);
CREATE INDEX IF NOT EXISTS ix_fact_orders_purchase   ON core.fact_orders (purchase_date_key);
CREATE INDEX IF NOT EXISTS ix_fact_items_product     ON core.fact_order_items (product_key);
CREATE INDEX IF NOT EXISTS ix_fact_items_seller      ON core.fact_order_items (seller_key);
