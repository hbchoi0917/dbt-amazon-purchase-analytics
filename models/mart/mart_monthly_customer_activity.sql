{{ config(materialized='table') }}

-- Monthly purchase activity of the fixed panel of participants.
-- Retention here is month-over-month: of the customers who bought last month, the share
-- who bought again this month. Classic acquisition cohorts are not possible with this
-- data (every participant was already an Amazon customer before 2018), and the panel
-- only includes people still active when surveyed, so levels skew high; trends and
-- seasonality are the reliable signal.

with customer_months as (
    select
        *,
        lag(is_active) over (partition by customer_id order by activity_month) as was_active_prior_month
    from {{ ref('int_customer_months') }}
),

monthly as (
    select
        activity_month,
        count(*) as panel_customers,
        sum(case when is_active then 1 else 0 end) as active_customers,
        sum(case when was_active_prior_month then 1 else 0 end) as prior_month_active_customers,
        sum(case when was_active_prior_month and is_active then 1 else 0 end) as retained_customers,
        sum(spend) as total_spend,
        sum(purchase_days) as purchase_days
    from customer_months
    group by activity_month
)

select
    activity_month,
    panel_customers,
    active_customers,
    round(active_customers * 100.0 / panel_customers, 2) as active_rate_pct,
    prior_month_active_customers,
    retained_customers,
    round(retained_customers * 100.0 / nullif(prior_month_active_customers, 0), 2) as mom_retention_pct,
    round(total_spend, 2) as total_spend,
    round(total_spend / nullif(active_customers, 0), 2) as spend_per_active_customer,
    round(purchase_days * 1.0 / nullif(active_customers, 0), 2) as purchase_days_per_active_customer
from monthly
