
--GROUP BY: the 20 months collapse into 2 rows (one per year)
SELECT year, SUM(revenue) AS year_revenue
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
GROUP BY year
ORDER BY year;

-- Window: all 20 months stay, and the grand total appears next to each one
SELECT year_month,
       revenue,
       SUM(revenue) OVER () AS total_revenue,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 1) AS pct_of_total
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
ORDER BY year_month;

-- Each month next to the total of ITS year
SELECT year,
       year_month,
       revenue,
       SUM(revenue) OVER (PARTITION BY year) AS year_revenue,
       ROUND(100.0 * revenue / SUM(revenue) OVER (PARTITION BY year), 1) AS pct_of_year
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
ORDER BY year_month;

-- Running total over all months, and a running total that restarts every year
SELECT year_month,
       revenue,
       SUM(revenue) OVER (ORDER BY year_month)                  AS running_total,
       SUM(revenue) OVER (PARTITION BY year ORDER BY year_month) AS running_total_in_year
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
ORDER BY year_month;

-- the 8 best categories by revenue
SELECT category,
       revenue,
       RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
FROM reporting.vw_sales_by_category
ORDER BY revenue_rank
LIMIT 8;

-- The 2 best revenue months of each year
WITH numbered AS (
    SELECT year,
           year_month,
           revenue,
           ROW_NUMBER() OVER (PARTITION BY year ORDER BY revenue DESC) AS rn
    FROM reporting.vw_monthly_sales
    WHERE year_month BETWEEN '2017-01' AND '2018-08'
)
SELECT year, year_month, revenue, rn
FROM numbered
WHERE rn <= 2
ORDER BY year, rn;

-- Revenue, last month's revenue, the change, and next month's revenue
SELECT year_month,
       revenue,
       LAG(revenue)  OVER w AS prev_month,
       revenue - LAG(revenue) OVER w AS change,
       ROUND(100.0 * (revenue - LAG(revenue) OVER w) / LAG(revenue) OVER w, 1) AS change_pct,
       LEAD(revenue) OVER w AS next_month
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
WINDOW w AS (ORDER BY year_month)
ORDER BY year_month;

-- 3-month moving average of orders
SELECT year_month,
       orders,
       ROUND(AVG(orders) OVER (ORDER BY year_month
                               ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS moving_avg_3m,
       COUNT(*) OVER (ORDER BY year_month
                      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS months_in_average
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
ORDER BY year_month;

-- Best month of the year, gap to the best, and the worst month
SELECT year,
       year_month,
       revenue,
       FIRST_VALUE(year_month) OVER (PARTITION BY year ORDER BY revenue DESC) AS best_month,
       revenue - FIRST_VALUE(revenue) OVER (PARTITION BY year ORDER BY revenue DESC) AS gap_to_best,
       LAST_VALUE(revenue) OVER (PARTITION BY year ORDER BY revenue DESC) AS last_value_trap,
       LAST_VALUE(revenue) OVER (PARTITION BY year ORDER BY revenue DESC
                                 ROWS BETWEEN UNBOUNDED PRECEDING
                                          AND UNBOUNDED FOLLOWING) AS worst_month_revenue
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
ORDER BY year, revenue DESC;

-- Each of the 74 categories gets a quartile (1 = biggest revenue)
SELECT category,
       revenue,
       NTILE(4) OVER (ORDER BY revenue DESC) AS quartile
FROM reporting.vw_sales_by_category
ORDER BY revenue DESC;

-- How much do the quartiles earn?
WITH q AS (
    SELECT category,
           revenue,
           NTILE(4) OVER (ORDER BY revenue DESC) AS quartile
    FROM reporting.vw_sales_by_category
)
SELECT quartile,
       COUNT(*)     AS categories,
       SUM(revenue) AS revenue
FROM q
GROUP BY quartile
ORDER BY quartile;

-- Orders per month versus the average month of the same year
SELECT year,
       year_month,
       orders,
       ROUND(AVG(orders) OVER (PARTITION BY year), 0)          AS avg_orders_in_year,
       orders - ROUND(AVG(orders) OVER (PARTITION BY year), 0) AS difference,
       CASE WHEN orders > AVG(orders) OVER (PARTITION BY year)
            THEN 'above average' ELSE 'below average' END      AS vs_average
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
ORDER BY year_month;

-- the 5 biggest categories and the % of TOTAL revenue each one makes (2 decimals).
SELECT category,
       revenue,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 2) AS pct_of_total
FROM reporting.vw_sales_by_category
ORDER BY revenue DESC
LIMIT 5;

-- orders per month with a running total of orders that restarts every year.
SELECT year_month,
       orders,
       SUM(orders) OVER (PARTITION BY year ORDER BY year_month) AS orders_ytd
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
ORDER BY year_month;

--rank the categories by revenue and show how much revenue each one is BEHIND the category just above it.
SELECT RANK() OVER (ORDER BY revenue DESC)                  AS revenue_rank,
       category,
       revenue,
       LAG(revenue) OVER (ORDER BY revenue DESC) - revenue   AS behind_previous
FROM reporting.vw_sales_by_category
ORDER BY revenue_rank
LIMIT 5;

--the 3 states with the most delivered orders (use RANK and a CTE).
WITH ranked AS (
    SELECT state,
           delivered_orders,
           RANK() OVER (ORDER BY delivered_orders DESC) AS state_rank
    FROM reporting.vw_delivery_by_state
)
SELECT state, delivered_orders, state_rank
FROM ranked
WHERE state_rank <= 3
ORDER BY state_rank;

--months where orders were ABOVE their own 3-month moving average.
WITH smoothed AS (
    SELECT year_month,
           orders,
           AVG(orders) OVER (ORDER BY year_month
                             ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS moving_avg_3m
    FROM reporting.vw_monthly_sales
    WHERE year_month BETWEEN '2017-01' AND '2018-08'
)
SELECT year_month, orders, ROUND(moving_avg_3m, 0) AS moving_avg_3m
FROM smoothed
WHERE orders > moving_avg_3m
ORDER BY year_month;