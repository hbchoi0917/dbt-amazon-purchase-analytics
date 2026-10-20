-- Exactly one method must be selected, consistently across horizons.

select count(distinct method) as selected_methods
from {{ ref('mart_revenue_forecast_accuracy') }}
where is_selected_method
having count(distinct method) <> 1
