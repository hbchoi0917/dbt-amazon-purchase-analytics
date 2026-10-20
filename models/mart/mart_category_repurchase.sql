{{ config(materialized='table') }}

-- How often does a customer who starts buying a category come back for more?
--
-- "New to category" = first purchase in the category after at least
-- category_lookback_months of observed history with none. The first months of the
-- window serve only as that lookback, which handles left-censoring (history starts in
-- 2018 for everyone). Only buyers with a full 180 days of follow-up inside the window
-- are counted, so the 30/90/180-day rates are not cut short at the end of the data.

with lines as (
    select customer_id, product_category, order_date
    from {{ ref('int_purchases__in_scope') }}
    where product_category <> 'UNKNOWN'
),

first_purchase as (
    select
        customer_id,
        product_category,
        min(order_date) as first_order_date
    from lines
    group by customer_id, product_category
),

new_to_category as (
    select *
    from first_purchase
    where first_order_date >= {{ dbt.dateadd('month', var('category_lookback_months'), "cast('" ~ var('analysis_start_date') ~ "' as date)") }}
      and first_order_date <= {{ dbt.dateadd('day', -180, "cast('" ~ var('analysis_end_date') ~ "' as date)") }}
),

next_purchase as (
    select
        n.customer_id,
        n.product_category,
        n.first_order_date,
        min(l.order_date) as second_order_date
    from new_to_category n
    left join lines l
        on n.customer_id = l.customer_id
        and n.product_category = l.product_category
        and l.order_date > n.first_order_date  -- a later day, not the same basket
    group by n.customer_id, n.product_category, n.first_order_date
),

measured as (
    select
        *,
        {{ dbt.datediff('first_order_date', 'second_order_date', 'day') }} as days_to_repurchase
    from next_purchase
)

select
    product_category,
    count(*) as new_buyers,
    round(100.0 * sum(case when days_to_repurchase <= 30 then 1 else 0 end) / count(*), 2) as repurchase_30d_pct,
    round(100.0 * sum(case when days_to_repurchase <= 90 then 1 else 0 end) / count(*), 2) as repurchase_90d_pct,
    round(100.0 * sum(case when days_to_repurchase <= 180 then 1 else 0 end) / count(*), 2) as repurchase_180d_pct,
    median(case when days_to_repurchase <= 180 then days_to_repurchase end) as median_days_to_repurchase_180d
from measured
group by product_category
having count(*) >= {{ var('category_min_new_buyers') }}
