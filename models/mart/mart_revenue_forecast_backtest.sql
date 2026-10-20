{{ config(materialized='table') }}

-- Out-of-sample backtest: from every historical cutoff, forecast 1..H months
-- ahead and compare against what actually happened.

with fits as (
    select * from {{ ref('int_revenue_forecast_fits') }}
),

actuals as (
    select revenue_month, revenue
    from {{ ref('int_monthly_revenue') }}
    where is_complete_month
),

horizons as (
    select cast(generated_number as integer) as horizon
    from ({{ dbt_utils.generate_series(upper_bound=var('forecast_horizon_months')) }}) as series
),

forecasts as (
    select
        f.method,
        f.origin_month,
        cast({{ dbt.dateadd('month', 'h.horizon', 'f.origin_month') }} as date) as target_month,
        h.horizon,
        f.train_months,
        f.base_level + f.trend_slope * h.horizon as forecast_revenue
    from fits f
    cross join horizons h
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
-- inner join keeps only targets that have a complete actual month to score against
inner join actuals a on f.target_month = a.revenue_month
