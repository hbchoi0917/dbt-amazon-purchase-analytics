-- Materialized as a table: 1.85M rows feed every downstream model.
{{ config(materialized='table') }}

with source as (
    select * from {{ source('open_ecommerce', 'amazon_purchases') }}
),

renamed as (
    select
        "Survey ResponseID"                                as customer_id,
        cast("Order Date" as date)                         as order_date,
        cast("Purchase Price Per Unit" as decimal(12, 2))  as unit_price,
        cast(cast("Quantity" as decimal(12, 1)) as integer) as quantity,  -- published as e.g. '1.0'
        "Shipping Address State"                           as shipping_state,
        "ASIN/ISBN (Product Code)"                         as product_code,
        "Title"                                            as product_title,
        "Category"                                         as product_category
    from source
),

-- The export has no order or line id, and ~18.5K rows are exact copies of another row.
-- They can be genuine repeat orders (same item, same price, same day), so they are kept;
-- duplicate_seq numbers identical rows so each one still gets a stable unique key.
numbered as (
    select
        *,
        row_number() over (
            partition by
                customer_id, order_date, unit_price, quantity,
                shipping_state, product_code, product_title, product_category
            order by customer_id
        ) as duplicate_seq
    from renamed
)

select
    {{ dbt_utils.generate_surrogate_key([
        'customer_id', 'order_date', 'unit_price', 'quantity', 'shipping_state',
        'product_code', 'product_title', 'product_category', 'duplicate_seq'
    ]) }} as purchase_line_id,
    customer_id,
    order_date,
    unit_price,
    quantity,
    unit_price * quantity as line_amount,
    shipping_state,
    product_code,
    product_title,
    coalesce(product_category, 'UNKNOWN') as product_category,
    coalesce(product_category = 'GIFT_CARD', false) as is_gift_card,
    duplicate_seq
from numbered
