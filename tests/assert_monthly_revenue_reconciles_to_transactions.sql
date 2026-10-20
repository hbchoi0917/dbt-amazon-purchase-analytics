-- Total revenue must survive the month spine and aggregation unchanged:
-- catches dropped months (spine too short) and join fan-out.

select
    (select sum(revenue) from {{ ref('int_monthly_revenue') }}) as monthly_total,
    (select sum(total_amount) from {{ ref('stg_transactions') }}) as transaction_total
where (select sum(revenue) from {{ ref('int_monthly_revenue') }})
   <> (select sum(total_amount) from {{ ref('stg_transactions') }})
