{{ config(materialized='table') }}

-- One row per customer per month in the analysis window, including months with no
-- purchases. The full grid is what makes active rates and month-over-month retention
-- correct: inactive months are rows with zero spend, not missing rows.
-- There is no order id in the export, so distinct purchase days stand in for orders.

with months as (
    select cast(date_month as date) as activity_month
    from (
        {{ dbt_utils.date_spine(
            datepart="month",
            start_date="cast('" ~ var('analysis_start_date') ~ "' as date)",
            end_date=dbt.dateadd('day', 1, "cast('" ~ var('analysis_end_date') ~ "' as date)")
        ) }}
    ) as spine
),

customers as (
    select customer_id from {{ ref('stg_ecommerce__customers') }}
),

monthly as (
    select
        customer_id,
        cast({{ dbt.date_trunc('month', 'order_date') }} as date) as activity_month,
        sum(line_amount) as spend,
        count(*) as purchase_lines,
        count(distinct order_date) as purchase_days
    from {{ ref('int_purchases__in_scope') }}
    group by 1, 2
)

select
    c.customer_id,
    m.activity_month,
    coalesce(p.spend, 0) as spend,
    coalesce(p.purchase_lines, 0) as purchase_lines,
    coalesce(p.purchase_days, 0) as purchase_days,
    p.customer_id is not null as is_active
from customers c
cross join months m
left join monthly p
    on c.customer_id = p.customer_id
    and m.activity_month = p.activity_month
