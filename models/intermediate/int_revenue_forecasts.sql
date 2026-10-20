-- Every method's forecast from every possible training cutoff ("origin"), 1..H months ahead.
-- Each origin sees only months up to and including itself (expanding window), so the
-- backtest replays exactly what was knowable at the time. The latest origin is the live
-- forecast and earlier origins feed the backtest: the evaluated code is the shipped code.

with series as (
    select
        revenue_month,
        revenue,
        row_number() over (order by revenue_month) as month_index
    from {{ ref('int_monthly_revenue') }}
),

origins as (
    select
        month_index as origin_index,
        revenue_month as origin_month
    from series
    where month_index >= {{ var('forecast_min_train_months') }}
),

horizons as (
    select cast(generated_number as integer) as horizon
    from ({{ dbt_utils.generate_series(upper_bound=var('forecast_horizon_months')) }}) as series
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
        avg(month_index) as mean_month_index,
        sum(case when month_index > origin_index - 12 then revenue end) as last_12m_revenue,
        sum(case when month_index between origin_index - 23 and origin_index - 12 then revenue end) as prior_12m_revenue
    from training
    group by origin_index, origin_month
),

grid as (
    select
        st.*,
        h.horizon,
        st.origin_index + h.horizon as target_index
    from stats st
    cross join horizons h
),

with_last_year as (
    select
        g.*,
        ly.revenue as same_month_last_year
    from grid g
    -- the target's month one year earlier; the extra condition keeps it inside the
    -- training window even if forecast_horizon_months is ever set above 12
    left join series ly
        on ly.month_index = g.target_index - 12
        and ly.month_index <= g.origin_index
),

forecasts as (
    select origin_month, horizon, train_months, 'naive' as method,
        last_revenue as forecast_revenue
    from with_last_year

    union all

    select origin_month, horizon, train_months, 'historical_mean' as method,
        mean_revenue as forecast_revenue
    from with_last_year

    union all

    select origin_month, horizon, train_months, 'moving_average' as method,
        moving_avg_revenue as forecast_revenue
    from with_last_year

    union all

    select origin_month, horizon, train_months, 'linear_trend' as method,
        mean_revenue + ols_slope * (target_index - mean_month_index) as forecast_revenue
    from with_last_year

    union all

    -- same month last year: captures seasonality, ignores growth
    select origin_month, horizon, train_months, 'seasonal_naive' as method,
        same_month_last_year as forecast_revenue
    from with_last_year

    union all

    -- same month last year scaled by trailing 12-month YoY growth: seasonality + level
    select origin_month, horizon, train_months, 'seasonal_naive_yoy' as method,
        same_month_last_year * last_12m_revenue / nullif(prior_12m_revenue, 0) as forecast_revenue
    from with_last_year
)

select
    origin_month,
    cast({{ dbt.dateadd('month', 'horizon', 'origin_month') }} as date) as target_month,
    horizon,
    method,
    train_months,
    forecast_revenue
from forecasts
