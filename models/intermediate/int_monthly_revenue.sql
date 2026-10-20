{{ config(materialized='view') }}

-- One row per calendar month, including months with no sales (revenue = 0).
-- The latest month is often still in progress (here: 2024-01 has a single day
-- of data), so is_complete_month lets forecast models train on full months only.

with transactions as (
    select * from {{ ref('stg_transactions') }}
),

bounds as (
    select
        cast({{ dbt.date_trunc('month', 'min(transaction_date)') }} as date) as first_month,
        cast({{ dbt.date_trunc('month', 'max(transaction_date)') }} as date) as last_month,
        max(transaction_date) as last_transaction_date
    from transactions
),

month_spine as (
    select
        cast({{ dbt.dateadd('month', 'series.generated_number - 1', 'bounds.first_month') }} as date) as revenue_month
    from ({{ dbt_utils.generate_series(upper_bound=var('revenue_spine_max_months')) }}) as series
    cross join bounds
    where {{ dbt.dateadd('month', 'series.generated_number - 1', 'bounds.first_month') }} <= bounds.last_month
),

monthly as (
    select
        cast({{ dbt.date_trunc('month', 'transaction_date') }} as date) as revenue_month,
        sum(total_amount) as revenue,
        count(*) as order_count,
        count(distinct customer_id) as customer_count
    from transactions
    group by 1
)

select
    s.revenue_month,
    coalesce(m.revenue, 0) as revenue,
    coalesce(m.order_count, 0) as order_count,
    coalesce(m.customer_count, 0) as customer_count,
    -- a month counts as complete once data exists through its last day
    b.last_transaction_date >= cast({{ dbt.last_day('s.revenue_month', 'month') }} as date) as is_complete_month
from month_spine s
cross join bounds b
left join monthly m on s.revenue_month = m.revenue_month
