-- The live forecast must be trained through the last month of the analysis window and
-- forecast only the months after it (where the panel's data is incomplete).

select f.*
from {{ ref('mart_revenue_forecast') }} f
where f.trained_through_month <> (select max(revenue_month) from {{ ref('int_monthly_revenue') }})
   or f.forecast_month <= cast('{{ var("analysis_end_date") }}' as date)
