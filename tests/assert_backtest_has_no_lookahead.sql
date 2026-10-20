-- Every forecast (backtest and live) must target a month strictly after its training
-- cutoff, exactly `horizon` months ahead, and be trained only on months up to the cutoff.

with months as (
    select revenue_month from {{ ref('int_monthly_revenue') }}
)

select f.*
from {{ ref('int_revenue_forecasts') }} f
where f.target_month <= f.origin_month
   or f.target_month <> cast({{ dbt.dateadd('month', 'f.horizon', 'f.origin_month') }} as date)
   or f.train_months <> (
        select count(*) from months m where m.revenue_month <= f.origin_month
   )
