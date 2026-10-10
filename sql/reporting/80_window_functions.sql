
--   1  OVER ()                 the big idea: keep your rows
--   2  PARTITION BY            a calculation per group
--   3  ORDER BY inside OVER    running totals
--   4  ROW_NUMBER/RANK/DENSE_RANK
--   5  top N per group         (needs a CTE)
--   6  LAG / LEAD              previous / next row
--   7  frames                  moving average
--   8  FIRST_VALUE/LAST_VALUE
--   9  NTILE                   equal buckets
--   10 group average           compare a row with its group


--The big idea: keep your rows
-- GROUP BY squeezes many rows into one. A window function does NOT squeeze: every row
-- stays, and the calculation is added as a NEW COLUMN next to it.
-- The words  OVER ()  mean: "do the calculation over all rows of the result".

-- 1a) GROUP BY: the 20 months collapse into 2 rows (one per year)
SELECT year, SUM(revenue) AS year_revenue
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
GROUP BY year
ORDER BY year;
--    year | year_revenue
--   ------+--------------
--    2017 |   6108492.27
--    2018 |   7341037.41

-- 1b) Window: all 20 months stay, and the grand total appears next to each one
SELECT year_month,
       revenue,
       SUM(revenue) OVER () AS total_revenue,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 1) AS pct_of_total
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
ORDER BY year_month;
--    year_month |  revenue  | total_revenue | pct_of_total
--   ------------+-----------+---------------+--------------
--    2017-01    | 120098.27 |   13449529.68 |          0.9
--    2017-02    | 244959.35 |   13449529.68 |          1.8
--    2017-03    | 368341.32 |   13449529.68 |          2.7
--    2017-04    | 353842.98 |   13449529.68 |          2.6


--PARTITION BY: a separate calculation for each group
-- PARTITION BY splits the rows into groups (like GROUP BY does) but, again, keeps every row.
-- The calculation restarts for each group. Here the groups are the years.

-- 2) Each month next to the total of ITS year
SELECT year,
       year_month,
       revenue,
       SUM(revenue) OVER (PARTITION BY year) AS year_revenue,
       ROUND(100.0 * revenue / SUM(revenue) OVER (PARTITION BY year), 1) AS pct_of_year
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
ORDER BY year_month;

--    year | year_month |  revenue  | year_revenue | pct_of_year
--   ------+------------+-----------+--------------+-------------
--    2017 | 2017-01    | 120098.27 |   6108492.27 |         2.0
--    2017 | 2017-02    | 244959.35 |   6108492.27 |         4.0
--    2017 | 2017-03    | 368341.32 |   6108492.27 |         6.0
--    2017 | 2017-04    | 353842.98 |   6108492.27 |         5.8


--ORDER BY inside OVER: running totals
-- Add ORDER BY inside OVER and the calculation becomes CUMULATIVE: each row sees itself and
-- all the rows before it. Useful for "year to date", "total so far", "cumulative sales".

-- 3) Running total over all months, and a running total that restarts every year
SELECT year_month,
       revenue,
       SUM(revenue) OVER (ORDER BY year_month)                  AS running_total,
       SUM(revenue) OVER (PARTITION BY year ORDER BY year_month) AS running_total_in_year
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
ORDER BY year_month;
--    year_month |  revenue   | running_total | running_total_in_year
--   ------------+------------+---------------+-----------------------
--    2017-01    |  120098.27 |     120098.27 |             120098.27
--    2017-02    |  244959.35 |     365057.62 |             365057.62
--    2017-03    |  368341.32 |     733398.94 |             733398.94
--    2017-04    |  353842.98 |    1087241.92 |            1087241.92
--    2017-05    |  503159.19 |    1590401.11 |            1590401.11
--    2017-06    |  429916.61 |    2020317.72 |            2020317.72
--    2017-07    |  492287.30 |    2512605.02 |            2512605.02
--    2017-08    |  568245.79 |    3080850.81 |            3080850.81
--    2017-09    |  621415.91 |    3702266.72 |            3702266.72
--    2017-10    |  660179.62 |    4362446.34 |            4362446.34
--    2017-11    | 1003862.14 |    5366308.48 |            5366308.48
--    2017-12    |  742183.79 |    6108492.27 |            6108492.27
--    2018-01    |  945456.29 |    7053948.56 |             945456.29
--    2018-02    |  837895.43 |    7891843.99 |            1783351.72
--   ... (20 rows in total, first 14 shown)
-- Look at 2018-01: running_total keeps growing, running_total_in_year starts again.
-- Remember: OVER (ORDER BY ...) = cumulative.   OVER (PARTITION BY ...) = restart per group.


--ROW_NUMBER, RANK and DENSE_RANK: numbering rows
-- Three ways to number rows. They only differ when there is a TIE:
--   ROW_NUMBER  1,2,3,4   never repeats (ties are numbered in an arbitrary order,
--                         so add a tie-breaker column to ORDER BY)
--   RANK        1,2,2,4   ties share a number, and the next number is skipped
--   DENSE_RANK  1,2,2,3   ties share a number, nothing is skipped


-- 4b) Same idea on real data: the 8 best categories by revenue
SELECT category,
       revenue,
       RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
FROM reporting.vw_sales_by_category
ORDER BY revenue_rank
LIMIT 8;
--          category        |  revenue   | revenue_rank
--   -----------------------+------------+--------------
--    health_beauty         | 1255695.13 |            1
--    watches_gifts         | 1198185.21 |            2
--    bed_bath_table        | 1035964.06 |            3
--    sports_leisure        |  979740.92 |            4
--    computers_accessories |  904322.02 |            5
--    furniture_decor       |  727465.05 |            6
--    housewares            |  626825.80 |            7
--    cool_stuff            |  620770.49 |            8



--Top N per group (ROW_NUMBER + PARTITION BY)
-- A very common question: "the best 2 months OF EACH YEAR".
-- Number the rows inside each group, then keep the first N.
-- You cannot write  WHERE row_num <= 2  in the same query, because WHERE runs BEFORE the
-- window function exists. So we number the rows in a CTE (a named sub-query) and filter
-- in the query that uses it.

-- 5) The 2 best revenue months of each year
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

--    year | year_month |  revenue   | rn
--   ------+------------+------------+----
--    2017 | 2017-11    | 1003862.14 |  1
--    2017 | 2017-12    |  742183.79 |  2
--    2018 | 2018-04    |  993592.98 |  1
--    2018 | 2018-05    |  992871.75 |  2


--LAG and LEAD: look at the previous / next row
-- LAG(x)  = the value of x on the PREVIOUS row (in the OVER ordering).
-- LEAD(x) = the value of x on the NEXT row.
-- Perfect for "change versus last month". The first row has no previous row, so you get NULL.
-- Tip: when you reuse the same OVER (...) many times, name it once with a WINDOW clause.

-- 6) Revenue, last month's revenue, the change, and next month's revenue
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

--    year_month |  revenue  | prev_month |  change   | change_pct | next_month
--   ------------+-----------+------------+-----------+------------+------------
--    2017-01    | 120098.27 |            |           |            |  244959.35
--    2017-02    | 244959.35 |  120098.27 | 124861.08 |      104.0 |  368341.32
--    2017-03    | 368341.32 |  244959.35 | 123381.97 |       50.4 |  353842.98
--    2017-04    | 353842.98 |  368341.32 | -14498.34 |       -3.9 |  503159.19
--    2017-05    | 503159.19 |  353842.98 | 149316.21 |       42.2 |  429916.61
--    2017-06    | 429916.61 |  503159.19 | -73242.58 |      -14.6 |  492287.30
-- Notice 2017-01 has NULL for prev_month. Window functions only see the rows left after WHERE
-- (December 2016 was filtered out). Try it: LAG(revenue, 2) looks two months back, and
-- LAG(revenue, 1, 0) gives 0 instead of NULL when there is no previous row.



--Moving average: choosing the frame (ROWS BETWEEN)
-- So far the window was "all rows before me". A FRAME lets you choose exactly which rows:
--   ROWS BETWEEN 2 PRECEDING AND CURRENT ROW  = me and the 2 rows before me (3 rows)
-- A moving average smooths out noisy months. COUNT(*) over the same frame shows how many
-- months were really averaged.

-- 7) 3-month moving average of orders
SELECT year_month,
       orders,
       ROUND(AVG(orders) OVER (ORDER BY year_month
                               ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS moving_avg_3m,
       COUNT(*) OVER (ORDER BY year_month
                      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS months_in_average
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
ORDER BY year_month;
--    year_month | orders | moving_avg_3m | months_in_average
--   ------------+--------+---------------+-------------------
--    2017-01    |    787 |           787 |                 1
--    2017-02    |   1718 |          1253 |                 2
--    2017-03    |   2617 |          1707 |                 3
--    2017-04    |   2377 |          2237 |                 3
--    2017-05    |   3640 |          2878 |                 3
--    2017-06    |   3205 |          3074 |                 3

-- The first two rows average fewer than 3 months (see months_in_average).
-- Try it: use  ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING  for a centered average.

-- FIRST_VALUE and LAST_VALUE: compare with the first / last row of a group
-- FIRST_VALUE(x) = x from the first row of the window, LAST_VALUE(x) = x from the last row.
-- Here we order each year's months from best to worst revenue.
-- WATCH OUT: when you add ORDER BY, the default frame stops at the CURRENT row, so LAST_VALUE
-- just returns the current row! To see the true last row, widen the frame to
-- ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING.

-- 8) Best month of the year, gap to the best, and the worst month (with the LAST_VALUE trap)
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

--    year | year_month |  revenue   | best_month | gap_to_best | last_value_trap | worst_month_revenue
--   ------+------------+------------+------------+-------------+-----------------+---------------------
--    2017 | 2017-11    | 1003862.14 | 2017-11    |        0.00 |      1003862.14 |           120098.27
--    2017 | 2017-12    |  742183.79 | 2017-11    |  -261678.35 |       742183.79 |           120098.27
--    2017 | 2017-10    |  660179.62 | 2017-11    |  -343682.52 |       660179.62 |           120098.27
--    2017 | 2017-09    |  621415.91 | 2017-11    |  -382446.23 |       621415.91 |           120098.27
--    2017 | 2017-08    |  568245.79 | 2017-11    |  -435616.35 |       568245.79 |           120098.27
--   ... (20 rows in total, first 5 shown)
-- last_value_trap is always equal to revenue (the current row): that is the trap.
-- worst_month_revenue is the real answer, thanks to the wider frame.


--NTILE: split rows into equal buckets
-- NTILE(4) deals the rows into 4 buckets of (almost) equal SIZE: quartiles.
-- Bucket 1 = the first 25% of the ordering, bucket 4 = the last 25%.
-- Use NTILE(10) for deciles, NTILE(100) for percentiles.

-- 9a) Each of the 74 categories gets a quartile (1 = biggest revenue)
SELECT category,
       revenue,
       NTILE(4) OVER (ORDER BY revenue DESC) AS quartile
FROM reporting.vw_sales_by_category
ORDER BY revenue DESC;

--       category    |  revenue   | quartile
--   ----------------+------------+----------
--    health_beauty  | 1255695.13 |        1
--    watches_gifts  | 1198185.21 |        1
--    bed_bath_table | 1035964.06 |        1
--    sports_leisure |  979740.92 |        1

-- 9b) How much do the quartiles earn? (use the window in a CTE, then GROUP BY it)
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

--    quartile | categories |   revenue
--   ----------+------------+-------------
--           1 |         19 | 11153438.60
--           2 |         19 |  1890408.63
--           3 |         18 |   400508.13
--           4 |         18 |    50045.38
-- The same number of categories in each bucket, but the first bucket earns most of the money.


-- Compare each row with its group's average

-- A window aggregate lets a row compare itself with its group, with no join and no sub-query:
-- "is this month above or below the average month of its year?"

-- 10) Orders per month versus the average month of the same year
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
-- Result:
--    year | year_month | orders | avg_orders_in_year | difference |  vs_average
--   ------+------------+--------+--------------------+------------+---------------
--    2017 | 2017-01    |    787 |               3698 |      -2911 | below average
--    2017 | 2017-02    |   1718 |               3698 |      -1980 | below average
--    2017 | 2017-03    |   2617 |               3698 |      -1081 | below average
--    2017 | 2017-04    |   2377 |               3698 |      -1321 | below average
--    2017 | 2017-05    |   3640 |               3698 |        -58 | below average
--    2017 | 2017-06    |   3205 |               3698 |       -493 | below average
--    2017 | 2017-07    |   3946 |               3698 |        248 | above average
--    2017 | 2017-08    |   4272 |               3698 |        574 | above average
--    2017 | 2017-09    |   4227 |               3698 |        529 | above average
--    2017 | 2017-10    |   4547 |               3698 |        849 | above average
--    2017 | 2017-11    |   7423 |               3698 |       3725 | above average
--    2017 | 2017-12    |   5620 |               3698 |       1922 | above average
--   ... (20 rows in total, first 12 shown)


-- the 5 biggest categories and the % of TOTAL revenue each one makes (2 decimals).
SELECT category,
       revenue,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 2) AS pct_of_total
FROM reporting.vw_sales_by_category
ORDER BY revenue DESC
LIMIT 5;
-- Result:
--          category        |  revenue   | pct_of_total
--   -----------------------+------------+--------------
--    health_beauty         | 1255695.13 |         9.31
--    watches_gifts         | 1198185.21 |         8.88
--    bed_bath_table        | 1035964.06 |         7.68
--    sports_leisure        |  979740.92 |         7.26
--    computers_accessories |  904322.02 |         6.70

-- orders per month with a running total of orders that restarts every year.
SELECT year_month,
       orders,
       SUM(orders) OVER (PARTITION BY year ORDER BY year_month) AS orders_ytd
FROM reporting.vw_monthly_sales
WHERE year_month BETWEEN '2017-01' AND '2018-08'
ORDER BY year_month;
-- Result:
--    year_month | orders | orders_ytd
--   ------------+--------+------------
--    2017-01    |    787 |        787
--    2017-02    |   1718 |       2505
--    2017-03    |   2617 |       5122
--    2017-04    |   2377 |       7499
--   ... (20 rows in total, first 4 shown)

--rank the categories by revenue and show how much revenue each one is BEHIND the category just above it.
SELECT RANK() OVER (ORDER BY revenue DESC)                  AS revenue_rank,
       category,
       revenue,
       LAG(revenue) OVER (ORDER BY revenue DESC) - revenue   AS behind_previous
FROM reporting.vw_sales_by_category
ORDER BY revenue_rank
LIMIT 5;
-- Result:
--    revenue_rank |       category        |  revenue   | behind_previous
--   --------------+-----------------------+------------+-----------------
--               1 | health_beauty         | 1255695.13 |
--               2 | watches_gifts         | 1198185.21 |        57509.92
--               3 | bed_bath_table        | 1035964.06 |       162221.15
--               4 | sports_leisure        |  979740.92 |        56223.14
--               5 | computers_accessories |  904322.02 |        75418.90

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
-- Result:
--    state | delivered_orders | state_rank
--   -------+------------------+------------
--    SP    |            40494 |          1
--    RJ    |            12350 |          2
--    MG    |            11354 |          3

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
-- Result:
--    year_month | orders | moving_avg_3m
--   ------------+--------+---------------
--    2017-02    |   1718 |          1253
--    2017-03    |   2617 |          1707
--    2017-04    |   2377 |          2237
--    2017-05    |   3640 |          2878
--    2017-06    |   3205 |          3074
--   ... (15 rows in total, first 5 shown)
