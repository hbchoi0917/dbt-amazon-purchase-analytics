{{ config(materialized='table') }}

-- Backtest accuracy per method and horizon. The method with the lowest overall
-- WAPE across all horizons is selected for the live forecast.

with backtest as (
    select * from {{ ref('mart_revenue_forecast_backtest') }}
),

by_horizon as (
    select
        method,
        horizon,
        count(*) as n_forecasts,
        avg(absolute_error) as mae,
        sqrt(avg(forecast_error * forecast_error)) as rmse,
        avg(absolute_pct_error) as mape_pct,
        sum(absolute_error) / nullif(sum(actual_revenue), 0) * 100 as wape_pct,
        -- positive = over-forecasting on average
        sum(forecast_error) / nullif(sum(actual_revenue), 0) * 100 as bias_pct
    from backtest
    group by method, horizon
),

overall as (
    select
        method,
        sum(absolute_error) / nullif(sum(actual_revenue), 0) * 100 as overall_wape_pct
    from backtest
    group by method
),

ranked as (
    select
        method,
        overall_wape_pct,
        row_number() over (order by overall_wape_pct, method) as method_rank
    from overall
)

select
    b.method,
    b.horizon,
    b.n_forecasts,
    round(b.mae, 2) as mae,
    round(b.rmse, 2) as rmse,
    round(b.mape_pct, 2) as mape_pct,
    round(b.wape_pct, 2) as wape_pct,
    round(b.bias_pct, 2) as bias_pct,
    round(r.overall_wape_pct, 2) as overall_wape_pct,
    r.method_rank,
    r.method_rank = 1 as is_selected_method
from by_horizon b
inner join ranked r on b.method = r.method
