-- The live forecast must start right after the last complete month, so a
-- partial month (e.g. 2024-01 with one day of data) is forecast, never trained on.

select f.*
from {{ ref('mart_revenue_forecast') }} f
where f.trained_through_month <> (
        select max(revenue_month)
        from {{ ref('int_monthly_revenue') }}
        where is_complete_month
   )
   or f.forecast_month <= f.trained_through_month
