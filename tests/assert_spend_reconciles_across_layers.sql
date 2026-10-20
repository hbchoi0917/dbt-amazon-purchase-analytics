-- Total in-scope spend must be identical at every layer: catches dropped or
-- duplicated rows in the customer-month grid, the monthly series and the activity mart.

with totals as (
    select 'int_purchases__in_scope' as layer, sum(line_amount) as total
    from {{ ref('int_purchases__in_scope') }}
    union all
    select 'int_customer_months', sum(spend) from {{ ref('int_customer_months') }}
    union all
    select 'int_monthly_revenue', sum(revenue) from {{ ref('int_monthly_revenue') }}
    union all
    select 'mart_monthly_customer_activity', sum(total_spend) from {{ ref('mart_monthly_customer_activity') }}
)

select *
from totals
where abs(total - (select total from totals where layer = 'int_purchases__in_scope')) > 0.01
