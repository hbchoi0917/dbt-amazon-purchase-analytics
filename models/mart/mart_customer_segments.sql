{{ config(materialized='table') }}

-- Spend and engagement by self-reported segment. One row per segment value, stacked
-- across segment types so a BI tool can filter on segment_type.
-- Segments smaller than segment_min_customers are suppressed (privacy floor).

with customer_totals as (
    select
        customer_id,
        sum(spend) as total_spend,
        sum(case when is_active then 1 else 0 end) as active_months,
        count(*) as panel_months
    from {{ ref('int_customer_months') }}
    group by customer_id
),

customers as (
    select
        c.*,
        t.total_spend / t.panel_months as monthly_spend,
        t.active_months * 100.0 / t.panel_months as active_month_pct
    from {{ ref('stg_ecommerce__customers') }} c
    inner join customer_totals t on c.customer_id = t.customer_id
),

segmented as (
    select 'age_group' as segment_type, age_group as segment_value, age_group_order as segment_order, *
    from customers

    union all

    select 'income_band' as segment_type, income_band as segment_value, income_band_order as segment_order, *
    from customers

    union all

    -- '1 (just me!)', '2', '3', '4+' sort correctly as text
    select 'household_size' as segment_type, household_size as segment_value, null as segment_order, *
    from customers

    union all

    select 'account_users' as segment_type, account_users as segment_value, null as segment_order, *
    from customers
)

select
    segment_type,
    segment_value,
    min(segment_order) as segment_order,
    count(*) as customers,
    round(avg(monthly_spend), 2) as avg_monthly_spend,
    round(median(monthly_spend), 2) as median_monthly_spend,
    round(avg(active_month_pct), 2) as avg_active_month_pct
from segmented
group by segment_type, segment_value
having count(*) >= {{ var('segment_min_customers') }}
