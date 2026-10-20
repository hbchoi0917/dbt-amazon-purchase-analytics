-- Repurchase within 30 days is a subset of within 90, which is a subset of within 180.

select *
from {{ ref('mart_category_repurchase') }}
where repurchase_30d_pct > repurchase_90d_pct
   or repurchase_90d_pct > repurchase_180d_pct
