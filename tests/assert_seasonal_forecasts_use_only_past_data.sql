-- seasonal_naive must equal actual revenue in the same month one year before the
-- target, and that month must already be known at the forecast origin.

select f.*
from {{ ref('int_revenue_forecasts') }} f
left join {{ ref('int_monthly_revenue') }} ly
    on ly.revenue_month = cast({{ dbt.dateadd('month', -12, 'f.target_month') }} as date)
where f.method = 'seasonal_naive'
  and (
        ly.revenue_month is null
     or ly.revenue_month > f.origin_month
     or abs(f.forecast_revenue - ly.revenue) > 0.01
  )
