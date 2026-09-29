CREATE TABLE IF NOT EXISTS orders_features(
    customer_id INTEGER,
    session_id TEXT,
    paid_orders_cnt INTEGER,
    paid_orders_without_promo_cnt INTEGER,
    paid_orders_without_promo_gmv NUMERIC,
    first_paid_order_without_promo_dttm TIMESTAMP
);

WITH filtered_orders AS (
    SELECT
        customer_id,
        session_id,
        order_status,
        promo_id,
        order_amount,
        created_dttm,
        CASE 
            WHEN order_status IN ('paid', 'completed') THEN 1 
            ELSE 0 
        END AS is_paid_or_completed,
        CASE 
            WHEN order_status IN ('paid', 'completed') AND ((promo_id IS NULL) OR (TRIM(promo_id) = '')) THEN 1 
            ELSE 0 
        END AS is_paid_completed_without_promo
    FROM orders
),
aggregated_orders AS (
    SELECT
        customer_id,
        session_id,
        SUM(is_paid_or_completed) AS paid_orders_cnt,
        SUM(is_paid_completed_without_promo) AS paid_orders_without_promo_cnt,
        SUM(
            CASE 
                WHEN is_paid_completed_without_promo = 1 
                THEN COALESCE(order_amount, 0) 
                ELSE 0 
            END
        ) AS paid_orders_without_promo_gmv,
        MIN(
            CASE 
                WHEN is_paid_completed_without_promo = 1 
                THEN created_dttm 
            END
        ) AS first_paid_order_without_promo_dttm
    FROM filtered_orders
    GROUP BY customer_id, session_id
)
INSERT INTO orders_features(
    customer_id,
    session_id,
    paid_orders_cnt,
    paid_orders_without_promo_cnt,
    paid_orders_without_promo_gmv,
    first_paid_order_without_promo_dttm
)
SELECT
    customer_id,
    session_id,
    paid_orders_cnt,
    paid_orders_without_promo_cnt,
    paid_orders_without_promo_gmv,
    first_paid_order_without_promo_dttm
FROM aggregated_orders;