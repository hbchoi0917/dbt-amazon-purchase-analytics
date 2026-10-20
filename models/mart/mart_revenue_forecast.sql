{{ config(materialized='table') }}

-- Forward forecast for the H months after the analysis window, from the latest origin.
-- All methods are kept so BI can compare them; is_selected_method marks the backtest
-- winner. The 80% interval uses the backtest RMSE at the same horizon
-- (approximate: assumes roughly normal, unbiased errors).

with latest as (
    select *
    from {{ ref('int_revenue_forecasts') }}
    where origin_month = (select max(origin_month) from {{ ref('int_revenue_forecasts') }})
),

accuracy as (
    select method, horizon, rmse, is_selected_method
    from {{ ref('mart_revenue_forecast_accuracy') }}
)

select
    f.target_month as forecast_month,
    f.horizon,
    f.method,
    f.origin_month as trained_through_month,
    f.train_months,
    round(f.forecast_revenue, 2) as forecast_revenue,
    round(greatest(f.forecast_revenue - 1.2816 * a.rmse, 0), 2) as lower_80_revenue,
    round(f.forecast_revenue + 1.2816 * a.rmse, 2) as upper_80_revenue,
    coalesce(a.is_selected_method, false) as is_selected_method
from latest f
left join accuracy a
    on f.method = a.method
    and f.horizon = a.horizon
