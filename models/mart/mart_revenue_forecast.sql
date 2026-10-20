{{ config(materialized='table') }}

-- Forward revenue forecast for the next H months from the latest complete month.
-- All methods are kept so BI can compare them; is_selected_method marks the
-- backtest winner. The 80% interval uses the backtest RMSE at the same horizon
-- (approximate: assumes roughly normal, unbiased errors).

with latest_fit as (
    select *
    from {{ ref('int_revenue_forecast_fits') }}
    where origin_month = (select max(origin_month) from {{ ref('int_revenue_forecast_fits') }})
),

accuracy as (
    select method, horizon, rmse, is_selected_method
    from {{ ref('mart_revenue_forecast_accuracy') }}
),

horizons as (
    select cast(generated_number as integer) as horizon
    from ({{ dbt_utils.generate_series(upper_bound=var('forecast_horizon_months')) }}) as series
),

forecasts as (
    select
        cast({{ dbt.dateadd('month', 'h.horizon', 'f.origin_month') }} as date) as forecast_month,
        h.horizon,
        f.method,
        f.origin_month as trained_through_month,
        f.train_months,
        f.base_level + f.trend_slope * h.horizon as forecast_revenue
    from latest_fit f
    cross join horizons h
)

select
    f.forecast_month,
    f.horizon,
    f.method,
    f.trained_through_month,
    f.train_months,
    round(f.forecast_revenue, 2) as forecast_revenue,
    round(greatest(f.forecast_revenue - 1.2816 * a.rmse, 0), 2) as lower_80_revenue,
    round(f.forecast_revenue + 1.2816 * a.rmse, 2) as upper_80_revenue,
    coalesce(a.is_selected_method, false) as is_selected_method
from forecasts f
left join accuracy a
    on f.method = a.method
    and f.horizon = a.horizon
