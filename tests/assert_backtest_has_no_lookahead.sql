-- Every backtest forecast must target a month strictly after its training cutoff,
-- exactly `horizon` months ahead, and be trained only on months up to the cutoff.

with complete_months as (
    select revenue_month
    from {{ ref('int_monthly_revenue') }}
    where is_complete_month
)

select b.*
from {{ ref('mart_revenue_forecast_backtest') }} b
where b.target_month <= b.origin_month
   or b.target_month <> cast({{ dbt.dateadd('month', 'b.horizon', 'b.origin_month') }} as date)
   or b.train_months <> (
        select count(*) from complete_months c where c.revenue_month <= b.origin_month
   )
