{{ config(materialized='table') }}

-- Out-of-sample backtest: every historical forecast scored against what actually happened.

with forecasts as (
    select * from {{ ref('int_revenue_forecasts') }}
),

actuals as (
    select revenue_month, revenue from {{ ref('int_monthly_revenue') }}
)

select
    f.method,
    f.origin_month,
    f.target_month,
    f.horizon,
    f.train_months,
    round(f.forecast_revenue, 2) as forecast_revenue,
    a.revenue as actual_revenue,
    round(f.forecast_revenue - a.revenue, 2) as forecast_error,
    round(abs(f.forecast_revenue - a.revenue), 2) as absolute_error,
    round(abs(f.forecast_revenue - a.revenue) / nullif(a.revenue, 0) * 100, 2) as absolute_pct_error
from forecasts f
-- inner join keeps only targets that already have an actual to score against
inner join actuals a on f.target_month = a.revenue_month
