-- Monthly spend of the whole panel (gift cards excluded): the series that is forecast.
-- Every month inside the analysis window is complete by construction.

select
    activity_month as revenue_month,
    sum(spend) as revenue,
    sum(case when is_active then 1 else 0 end) as active_customers,
    sum(purchase_lines) as purchase_lines
from {{ ref('int_customer_months') }}
group by activity_month
