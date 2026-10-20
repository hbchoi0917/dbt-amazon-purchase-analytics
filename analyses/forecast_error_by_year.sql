-- Backtest error by method and target year (1-month-ahead forecasts).
-- Shows how method rankings shift between the 2020 COVID jump and the calmer 2022.
-- Compile with `dbt compile -s forecast_error_by_year` and run the SQL in target/.

select
    method,
    extract(year from target_month) as target_year,
    count(*) as n_forecasts,
    round(sum(absolute_error) / sum(actual_revenue) * 100, 1) as wape_pct,
    round(sum(forecast_error) / sum(actual_revenue) * 100, 1) as bias_pct
from {{ ref('mart_revenue_forecast_backtest') }}
where horizon = 1
group by 1, 2
order by 2, 4
