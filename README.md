# Nifty 50 Momentum Strategy

Rules-based 6-month momentum strategy backtested on Nifty 50 stocks (Aug 2023–Jun 2026) using SQL window functions and CTEs, with a Random Forest ML layer for portfolio-level stock selection. Built with Python, SQLite, and Google Colab.

---

## Project Overview

This project tests a classic factor investing idea on Indian equity markets: **do stocks that have recently outperformed tend to keep outperforming?**

Every month, all 50 Nifty 50 stocks are ranked by their trailing 6-month return. The top 10 are held equally weighted for the next month. This is repeated across 35 monthly rebalance points and compared against the Nifty 50 index as a benchmark.

A Random Forest classifier is then layered on top to see whether ML-based stock selection improves on the simple rules-based approach.

---

## Results Summary

| Metric | Rules-Based Strategy | ML Strategy | Nifty 50 Index |
|---|---|---|---|
| Period | Aug 2023 – May 2026 | Jan 2025 – May 2026 | Aug 2023 – May 2026 |
| Months Tested | 35 | 17 | 35 |
| Hit Rate | 65.7% | 41.2% | — |
| Cumulative Return | 39.6% | 9.40% | 21.9% |
| Avg Monthly Return | 1.08% | — | 0.65% |
| Monthly Alpha | +0.43% | — | — |

> ML hit rate and cumulative return cover the test period only (Jan 2025–May 2026). Rules-based covers the full backtest period.

---

## Strategy Rules

1. **Universe** — All 50 Nifty 50 constituents with continuous price history
2. **Formation** — Compute trailing 6-month return for each stock at month-end
3. **Ranking** — Rank all 50 stocks cross-sectionally by 6-month momentum
4. **Portfolio** — Go long the top 10 stocks, equally weighted
5. **Holding Period** — Hold for 1 calendar month
6. **Rebalance** — Repeat every month (35 rebalance points, Aug 2023–May 2026)

---

## SQL Techniques Used

| Technique | Purpose |
|---|---|
| `ROW_NUMBER() OVER (PARTITION BY ticker, month ORDER BY date DESC)` | Extract last trading day of each month |
| `LAG(close, 1)` | Compute 1-month return |
| `LAG(close, 6)` | Compute 6-month momentum score |
| `RANK() OVER (PARTITION BY month ORDER BY momentum_6m DESC)` | Cross-sectional ranking each month |
| Self-join | Link top-10 picks to their forward (next month) returns |
| `CASE WHEN` | Flag whether strategy beat the index each month |
| Anti-join (`LEFT JOIN ... WHERE IS NULL`) | Find stocks that never appeared in the top 10 |

All queries are in [`queries.sql`](queries.sql).

---

## ML Layer

**Model:** Random Forest Classifier (scikit-learn)

**Target:** Will this stock beat the Nifty 50 index next month? (1 = Yes, 0 = No)

**Features:**
- 1-month return
- 3-month return
- 6-month return
- 12-month return
- 6-month return volatility
- Cross-sectional momentum rank

**Train/Test Split:** Train on 2023–2024, test on 2025–2026

**Key finding:** Individual stock classification accuracy was ~50% (coin flip), but at the portfolio level the ML strategy returned 9.40% vs 2.33% for rules-based and -0.41% for the index over the same test period. This mirrors how factor investing works in practice — the edge is at the basket level, not the individual stock level.

---

## Data Pipeline

- **Source:** GOOGLEFINANCE via Google Sheets (51 tabs — 50 stocks + Nifty 50 index)
- **Coverage:** Jan 2023 – Jun 2026 (daily closes)
- **Rows:** 42,507 rows × 3 columns (ticker, date, close)
- **Database:** SQLite via Google Colab
- **Benchmark:** `INDEXNSE:NIFTY_50`

---

## Project Structure

```
nifty50-momentum-strategy/
│
├── queries.sql                  # All SQL queries (annotated)
├── README.md                    # This file
├── Nifty50_Momentum_Strategy.pptx  # Presentation deck (9 slides)
```

---

## Key Insights

- **Momentum works on Nifty 50** — trailing 6-month winners consistently outperform in the following month, generating nearly double the index return over 35 months.
- **ML adds portfolio-level value despite low individual accuracy** — the model's probability scores shift which stocks enter the top-10, and those marginal changes improve aggregate returns.
- **Momentum crash risk is real** — March 2026 (-14.35% strategy vs -11.31% index) shows the strategy amplifies drawdowns during sharp market reversals.

---

## Limitations

- No transaction costs or slippage modeled
- Small universe (50 stocks) — broader index would give more robust signal
- ML trained on only ~24 months of data
- No fundamental features (earnings, P/E, ROE) in the ML model
- Survivorship bias — current Nifty 50 constituents used throughout

---

## Tech Stack

`Python` · `SQLite` · `pandas` · `scikit-learn` · `matplotlib` · `Google Colab` · `Google Sheets`

---

## Author

Aarav · Finance & Data Science Intern, Indiabulls Securities  
Part of a 5-project portfolio targeting Analyst / Risk Manager / Portfolio Manager roles.
