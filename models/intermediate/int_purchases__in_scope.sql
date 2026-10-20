-- Analysis-grade purchase lines: every spend metric starts here.
--   * inside the analysis window: participants exported their data between Nov 2022 and
--     Mar 2023, so later months are incomplete (and 18 rows carry dates up to 2024)
--   * gift cards excluded: buying one is a prepayment; what it funds is already counted

select *
from {{ ref('stg_ecommerce__purchases') }}
where order_date between cast('{{ var("analysis_start_date") }}' as date)
                     and cast('{{ var("analysis_end_date") }}' as date)
  and not is_gift_card
