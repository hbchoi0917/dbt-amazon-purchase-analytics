-- The customer x month grid must contain every customer for every month of the
-- analysis window (inactive months as zero rows), or activity rates would be inflated.

with expected as (
    select
        (select count(*) from {{ ref('stg_ecommerce__customers') }})
        * (1 + {{ dbt.datediff(
                "cast('" ~ var('analysis_start_date') ~ "' as date)",
                "cast('" ~ var('analysis_end_date') ~ "' as date)",
                'month') }}) as expected_rows
),

actual as (
    select count(*) as actual_rows from {{ ref('int_customer_months') }}
)

select *
from expected
cross join actual
where expected_rows <> actual_rows
