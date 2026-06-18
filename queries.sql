-- ============================================================
-- Nifty 50 Momentum Strategy — SQL Queries
-- Database: SQLite (Google Colab)
-- Table: price_history (ticker TEXT, date TEXT, close REAL)
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- QUERY 1: Month-End Price Extraction
-- Technique: ROW_NUMBER() window function
-- Purpose: Pick the last trading day of each month per ticker
-- ─────────────────────────────────────────────────────────────

WITH month_end AS (
  SELECT ticker, date, close,
         strftime('%Y-%m', date) AS month,
         ROW_NUMBER() OVER (
           PARTITION BY ticker, strftime('%Y-%m', date)
           ORDER BY date DESC
         ) AS rn
  FROM price_history
)
SELECT ticker, month, date, close
FROM month_end
WHERE rn = 1
ORDER BY ticker, month;


-- ─────────────────────────────────────────────────────────────
-- QUERY 2: Monthly Returns + 6-Month Momentum Score
-- Technique: LAG() window function
-- Purpose: Compute 1-month return and 6-month lookback return
-- ─────────────────────────────────────────────────────────────

WITH month_end AS (
  SELECT ticker, date, close,
         strftime('%Y-%m', date) AS month,
         ROW_NUMBER() OVER (
           PARTITION BY ticker, strftime('%Y-%m', date)
           ORDER BY date DESC
         ) AS rn
  FROM price_history
),
monthly_prices AS (
  SELECT ticker, month, date, close FROM month_end WHERE rn = 1
)
SELECT ticker, month, close,
       close / LAG(close, 1) OVER (PARTITION BY ticker ORDER BY month) - 1 AS monthly_return,
       close / LAG(close, 6) OVER (PARTITION BY ticker ORDER BY month) - 1 AS momentum_6m
FROM monthly_prices
ORDER BY ticker, month;


-- ─────────────────────────────────────────────────────────────
-- QUERY 3: Cross-Sectional Ranking by Momentum
-- Technique: RANK() window function partitioned by month
-- Purpose: Rank all 50 stocks against each other within each month
-- ─────────────────────────────────────────────────────────────

WITH month_end AS (
  SELECT ticker, date, close,
         strftime('%Y-%m', date) AS month,
         ROW_NUMBER() OVER (
           PARTITION BY ticker, strftime('%Y-%m', date)
           ORDER BY date DESC
         ) AS rn
  FROM price_history
),
monthly_prices AS (
  SELECT ticker, month, close FROM month_end WHERE rn = 1
),
monthly_returns AS (
  SELECT ticker, month, close,
         close / LAG(close, 1) OVER (PARTITION BY ticker ORDER BY month) - 1 AS monthly_return,
         close / LAG(close, 6) OVER (PARTITION BY ticker ORDER BY month) - 1 AS momentum_6m
  FROM monthly_prices
)
SELECT ticker, month,
       ROUND(momentum_6m * 100, 2) AS momentum_pct,
       RANK() OVER (PARTITION BY month ORDER BY momentum_6m DESC) AS momentum_rank
FROM monthly_returns
WHERE ticker != 'NIFTY50_INDEX'
  AND momentum_6m IS NOT NULL
ORDER BY month, momentum_rank;


-- ─────────────────────────────────────────────────────────────
-- QUERY 4: Top 10 Picks Per Month
-- Technique: CTE chaining + RANK filter
-- Purpose: Select top 10 momentum stocks for each formation month
-- ─────────────────────────────────────────────────────────────

WITH month_end AS (
  SELECT ticker, date, close,
         strftime('%Y-%m', date) AS month,
         ROW_NUMBER() OVER (
           PARTITION BY ticker, strftime('%Y-%m', date)
           ORDER BY date DESC
         ) AS rn
  FROM price_history
),
monthly_prices AS (
  SELECT ticker, month, close FROM month_end WHERE rn = 1
),
monthly_returns AS (
  SELECT ticker, month, close,
         close / LAG(close, 1) OVER (PARTITION BY ticker ORDER BY month) - 1 AS monthly_return,
         close / LAG(close, 6) OVER (PARTITION BY ticker ORDER BY month) - 1 AS momentum_6m
  FROM monthly_prices
),
ranked AS (
  SELECT *,
         RANK() OVER (PARTITION BY month ORDER BY momentum_6m DESC) AS momentum_rank
  FROM monthly_returns
  WHERE ticker != 'NIFTY50_INDEX'
    AND momentum_6m IS NOT NULL
)
SELECT ticker, month,
       ROUND(momentum_6m * 100, 2) AS momentum_pct,
       momentum_rank
FROM ranked
WHERE momentum_rank <= 10
ORDER BY month, momentum_rank;


-- ─────────────────────────────────────────────────────────────
-- QUERY 5: Self-Join — Top Picks to Forward Returns
-- Technique: Self-join on monthly_returns
-- Purpose: For each month's top-10 picks, get their actual return
--          the FOLLOWING month (the holding period return)
-- ─────────────────────────────────────────────────────────────

WITH month_end AS (
  SELECT ticker, date, close,
         strftime('%Y-%m', date) AS month,
         ROW_NUMBER() OVER (
           PARTITION BY ticker, strftime('%Y-%m', date)
           ORDER BY date DESC
         ) AS rn
  FROM price_history
),
monthly_prices AS (
  SELECT ticker, month, close FROM month_end WHERE rn = 1
),
monthly_returns AS (
  SELECT ticker, month, close,
         close / LAG(close, 1) OVER (PARTITION BY ticker ORDER BY month) - 1 AS monthly_return,
         close / LAG(close, 6) OVER (PARTITION BY ticker ORDER BY month) - 1 AS momentum_6m
  FROM monthly_prices
),
ranked AS (
  SELECT *,
         RANK() OVER (PARTITION BY month ORDER BY momentum_6m DESC) AS momentum_rank
  FROM monthly_returns
  WHERE ticker != 'NIFTY50_INDEX'
    AND momentum_6m IS NOT NULL
),
top_picks AS (
  SELECT * FROM ranked WHERE momentum_rank <= 10
)
SELECT t.ticker,
       t.month AS formation_month,
       mr.month AS holding_month,
       ROUND(mr.monthly_return * 100, 2) AS stock_return_pct
FROM top_picks t
JOIN monthly_returns mr
  ON mr.ticker = t.ticker
 AND mr.month = strftime('%Y-%m', date(t.month || '-01', '+1 month'))
ORDER BY t.month, stock_return_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- QUERY 6: Full Backtest — Strategy vs Benchmark (CASE WHEN)
-- Technique: Multi-CTE chain + benchmark join + CASE WHEN
-- Purpose: Aggregate top-10 returns each month, compare to index,
--          flag whether strategy beat the benchmark
-- ─────────────────────────────────────────────────────────────

WITH month_end AS (
  SELECT ticker, date, close,
         strftime('%Y-%m', date) AS month,
         ROW_NUMBER() OVER (
           PARTITION BY ticker, strftime('%Y-%m', date)
           ORDER BY date DESC
         ) AS rn
  FROM price_history
),
monthly_prices AS (
  SELECT ticker, month, close FROM month_end WHERE rn = 1
),
monthly_returns AS (
  SELECT ticker, month, close,
         close / LAG(close, 1) OVER (PARTITION BY ticker ORDER BY month) - 1 AS monthly_return,
         close / LAG(close, 6) OVER (PARTITION BY ticker ORDER BY month) - 1 AS momentum_6m
  FROM monthly_prices
),
ranked AS (
  SELECT *,
         RANK() OVER (PARTITION BY month ORDER BY momentum_6m DESC) AS momentum_rank
  FROM monthly_returns
  WHERE ticker != 'NIFTY50_INDEX'
    AND momentum_6m IS NOT NULL
),
top_picks AS (SELECT * FROM ranked WHERE momentum_rank <= 10),
portfolio_returns AS (
  SELECT t.month AS formation_month,
         strftime('%Y-%m', date(t.month || '-01', '+1 month')) AS holding_month,
         AVG(mr.monthly_return) AS portfolio_return
  FROM top_picks t
  JOIN monthly_returns mr
    ON mr.ticker = t.ticker
   AND mr.month = strftime('%Y-%m', date(t.month || '-01', '+1 month'))
  GROUP BY t.month
),
benchmark AS (
  SELECT month, monthly_return AS benchmark_return
  FROM monthly_returns
  WHERE ticker = 'NIFTY50_INDEX'
)
SELECT p.holding_month,
       ROUND(p.portfolio_return * 100, 2) AS strategy_pct,
       ROUND(b.benchmark_return * 100, 2) AS index_pct,
       CASE
         WHEN p.portfolio_return > b.benchmark_return THEN 'Beat Index'
         ELSE 'Underperformed'
       END AS result
FROM portfolio_returns p
JOIN benchmark b ON b.month = p.holding_month
ORDER BY p.holding_month;


-- ─────────────────────────────────────────────────────────────
-- QUERY 7: Anti-Join — Stocks Never in Top 10
-- Technique: LEFT JOIN ... WHERE IS NULL (anti-join pattern)
-- Purpose: Find stocks that never appeared in the top-10 picks
--          across all 35 formation months
-- ─────────────────────────────────────────────────────────────

WITH month_end AS (
  SELECT ticker, date, close,
         strftime('%Y-%m', date) AS month,
         ROW_NUMBER() OVER (
           PARTITION BY ticker, strftime('%Y-%m', date)
           ORDER BY date DESC
         ) AS rn
  FROM price_history
),
monthly_prices AS (
  SELECT ticker, month, close FROM month_end WHERE rn = 1
),
monthly_returns AS (
  SELECT ticker, month,
         close / LAG(close, 6) OVER (PARTITION BY ticker ORDER BY month) - 1 AS momentum_6m
  FROM monthly_prices
),
ranked AS (
  SELECT *,
         RANK() OVER (PARTITION BY month ORDER BY momentum_6m DESC) AS momentum_rank
  FROM monthly_returns
  WHERE ticker != 'NIFTY50_INDEX'
    AND momentum_6m IS NOT NULL
),
ever_picked AS (
  SELECT DISTINCT ticker FROM ranked WHERE momentum_rank <= 10
),
all_tickers AS (
  SELECT DISTINCT ticker FROM price_history WHERE ticker != 'NIFTY50_INDEX'
)
SELECT a.ticker
FROM all_tickers a
LEFT JOIN ever_picked e ON a.ticker = e.ticker
WHERE e.ticker IS NULL
ORDER BY a.ticker;
