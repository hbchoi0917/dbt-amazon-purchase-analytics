{{ config(materialized='view') }}

-- Fits every forecast method at every possible training cutoff ("origin").
-- Each origin sees only complete months up to and including itself (expanding
-- window), so the backtest replays exactly what was knowable at that time.
-- The latest origin drives the live forecast; earlier origins feed the backtest,
-- so the model that is evaluated is the same code that is shipped.
--
-- Every method is expressed as: forecast(h months ahead) = base_level + trend_slope * h

with series as (
    select
        revenue_month,
        revenue,
        row_number() over (order by revenue_month) as month_index
    from {{ ref('int_monthly_revenue') }}
    where is_complete_month
),

origins as (
    select
        month_index as origin_index,
        revenue_month as origin_month
    from series
    where month_index >= {{ var('forecast_min_train_months') }}
),

training as (
    select
        o.origin_index,
        o.origin_month,
        s.month_index,
        s.revenue
    from origins o
    inner join series s on s.month_index <= o.origin_index
),

stats as (
    select
        origin_index,
        origin_month,
        count(*) as train_months,
        avg(revenue) as mean_revenue,
        max(case when month_index = origin_index then revenue end) as last_revenue,
        avg(case when month_index > origin_index - {{ var('forecast_moving_average_months') }} then revenue end) as moving_avg_revenue,
        -- OLS slope as covariance / variance: portable across warehouses (no regr_slope)
        covar_pop(revenue, month_index) / nullif(var_pop(month_index), 0) as ols_slope,
        avg(month_index) as mean_month_index
    from training
    group by origin_index, origin_month
)

select origin_month, train_months, 'naive' as method, last_revenue as base_level, 0.0 as trend_slope
from stats

union all

select origin_month, train_months, 'historical_mean' as method, mean_revenue as base_level, 0.0 as trend_slope
from stats

union all

select origin_month, train_months, 'moving_average' as method, moving_avg_revenue as base_level, 0.0 as trend_slope
from stats

union all

-- fitted value of the regression line at the origin, extended by the slope
select
    origin_month,
    train_months,
    'linear_trend' as method,
    mean_revenue + ols_slope * (origin_index - mean_month_index) as base_level,
    ols_slope as trend_slope
from stats
